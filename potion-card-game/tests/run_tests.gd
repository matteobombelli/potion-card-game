extends SceneTree
## Headless rules tests: godot --headless --path . -s res://tests/run_tests.gd
## These pin down the current Rules numbers; update them alongside rules.gd.

const C := CardData.CardColor
const M := CardData.Modifier
const K := SpecialOrder.Kind
const LEFT := GameState.Side.LEFT
const RIGHT := GameState.Side.RIGHT

var _fails := 0
var _passes := 0


func _init() -> void:
	test_deck()
	test_dealing()
	test_scoring_basics()
	test_bonuses()
	test_orders()
	test_order_flow()
	test_turn_validation()
	test_swap()
	test_full_games()
	test_determinism()
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func card(color: int, value := 1, mod := M.NONE, mod_color := C.BLACK) -> CardData:
	return CardData.make(0, color, value, mod, mod_color)


## Chooses orders for everyone so the game is in the PLAY phase.
func choose_all_orders(gs: GameState, pick := 0) -> void:
	while gs.phase == GameState.Phase.CHOOSE_ORDER:
		gs.choose_order(gs.current_player, pick)


## Plays legal moves (first non-empty deck, alternating sides, skipping swaps) until the round ends.
func play_out_round(gs: GameState) -> int:
	var turns := 0
	choose_all_orders(gs)
	while gs.phase != GameState.Phase.ROUND_OVER:
		var p := gs.current_player
		var deck := 0
		while not gs.can_play(p, deck):
			deck += 1
		check(gs.play_card(p, deck, LEFT if turns % 2 else RIGHT), "play card")
		if gs.phase == GameState.Phase.SWAP:
			check(gs.skip_swap(p), "skip swap")
		turns += 1
	return turns


# --- Deck ---------------------------------------------------------------------

func test_deck() -> void:
	var deck := DeckBuilder.build_full_deck()
	check(deck.size() == 96, "deck has 96 cards (got %d)" % deck.size())
	var black := deck.filter(func(c): return c.is_black())
	check(black.size() == 16, "16 black cards")
	check(black.filter(func(c): return c.value == 0 and not c.has_modifier()).size() == 4, "4x black 0, no modifier")
	for spec in [[M.LEFT, -1], [M.RIGHT, -1], [M.GLOBAL, -2]]:
		var ms := black.filter(func(c): return c.modifier == spec[0])
		check(ms.size() == 4, "4 black cards with modifier %d" % spec[0])
		check(ms.all(func(c): return c.value == spec[1]), "black modifier %d cards are worth %d" % spec)
		var icons := {}
		for c in ms:
			icons[c.modifier_color] = true
		check(icons.size() == 4 and not icons.has(C.BLACK), "black modifier icons are R/G/B/Y, never black")
	for color in Rules.SUITS:
		var cs := deck.filter(func(c): return c.color == color)
		check(cs.size() == 20, "20 cards of colour %d" % color)
		check(cs.filter(func(c): return not c.has_modifier() and c.value == 1).size() == 5, "5 plain +1")
		for mod in [M.LEFT, M.RIGHT, M.GLOBAL]:
			var ms := cs.filter(func(c): return c.modifier == mod)
			check(ms.size() == 5, "5 of modifier %d" % mod)
			var icons := {}
			for c in ms:
				icons[c.modifier_color] = true
				check(c.value == (0 if mod == M.GLOBAL else 1), "modifier card value")
			check(icons.size() == 5, "modifier colours cover R/G/B/Y/Black")
	var ids := {}
	for c in deck:
		ids[c.id] = true
	check(ids.size() == 96, "unique ids")


func test_dealing() -> void:
	for n in [3, 4, 5]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var decks := DeckBuilder.deal_middle_decks(n, rng)
		check(decks.size() == n, "%d decks" % n)
		var sizes: Array = decks.map(func(d): return d.size())
		var blacks: Array = decks.map(func(d): return d.filter(func(c): return c.is_black()).size())
		check(sizes.reduce(func(a, b): return a + b, 0) == 96, "all cards dealt into %d decks" % n)
		check(sizes.max() - sizes.min() <= 1, "decks even for %d decks: %s" % [n, sizes])
		check(blacks.max() - blacks.min() <= 1, "black split evenly for %d decks: %s" % [n, blacks])


# --- Scoring ------------------------------------------------------------------

func test_scoring_basics() -> void:
	var r := Scoring.score_potion([card(C.RED), card(C.RED), card(C.BLUE), card(C.BLACK, -2)])
	check(r.base == [1, 1, 1, -2], "base values")
	check(r.mod_hits.is_empty(), "no modifier hits")

	# LHS at left edge does nothing; RHS at right edge does nothing.
	r = Scoring.score_potion([card(C.RED, 1, M.LEFT, C.RED), card(C.BLUE), card(C.GREEN), card(C.YELLOW, 1, M.RIGHT, C.RED)])
	check(r.mod_hits.is_empty(), "edge modifiers have no target")

	r = Scoring.score_potion([card(C.BLUE), card(C.RED, 1, M.LEFT, C.BLUE), card(C.GREEN, 1, M.RIGHT, C.YELLOW), card(C.YELLOW)])
	check(r.mod_hits.size() == 2, "LHS and RHS both hit")
	check(r.mod_hits[0].dst == 0 and r.mod_hits[1].dst == 3, "hit targets")

	r = Scoring.score_potion([card(C.RED, 0, M.GLOBAL, C.RED), card(C.RED), card(C.BLUE), card(C.GREEN)])
	check(r.mod_hits.size() == 2, "global counts itself")
	check(r.total == 3 + 2, "total = base + modifiers, no combo (got %d)" % r.total)
	r = Scoring.score_potion([card(C.RED, 0, M.GLOBAL, C.BLACK), card(C.BLACK, -1), card(C.BLUE), card(C.GREEN)])
	check(r.mod_hits.size() == 1 and r.mod_hits[0].dst == 1, "black global icon matches black card")


func test_bonuses() -> void:
	var cases := [
		[[C.RED, C.RED, C.RED, C.RED], "Samsies", 4],
		[[C.BLACK, C.BLACK, C.BLACK, C.RED], "Oops", 4],      # flat +4, beats Black Sheep
		[[C.BLACK, C.BLACK, C.RED, C.RED], "Oops", 4],        # beats Twin
		[[C.RED, C.YELLOW, C.GREEN, C.BLUE], "Rainbow", 5],   # beats Calico
		[[C.BLUE, C.YELLOW, C.GREEN, C.RED], "Calico", 2],    # wrong order is only Calico
		[[C.RED, C.BLACK, C.GREEN, C.BLUE], "Calico", 2],     # black counts as a colour
		[[C.GREEN, C.GREEN, C.GREEN, C.BLUE], "Black Sheep", 2],
		[[C.GREEN, C.BLUE, C.GREEN, C.BLUE], "Twin", 2],
		[[C.GREEN, C.GREEN, C.RED, C.BLUE], "", 0],
	]
	for c in cases:
		var cards: Array = c[0].map(func(col): return card(col, -1 if col == C.BLACK else 1))
		var b := Scoring.best_bonus(cards)
		check(b.name == c[1] and b.pts == c[2], "%s -> %s +%d (got %s +%d)" % [c[0], c[1], c[2], b.name, b.pts])
	check(Scoring.best_bonus([card(C.RED), card(C.RED)]).pts == 0, "incomplete potion has no bonus")


# --- Special orders -----------------------------------------------------------

func test_orders() -> void:
	var deck := SpecialOrder.build_deck()
	check(deck.size() == 20, "20 special orders")
	var count := func(k): return deck.filter(func(o): return o.kind == k).size()
	check(count.call(K.OUTSIDE_COLOR) == 4 and count.call(K.LACKS_COLOR) == 4, "4 outside + 4 lacks")
	check(count.call(K.ALL_MODIFIERS) == 4 and count.call(K.NO_MODIFIER_BONUS) == 4, "4 all-mod + 4 no-mod")
	check(count.call(K.OOPS_TWIN) == 2 and count.call(K.BASE_ZERO) == 2, "2 oops-twin + 2 base-0")
	var pts := {}
	for o in deck:
		pts[o.kind] = o.points
	check(pts == { K.OUTSIDE_COLOR: 2, K.LACKS_COLOR: 2, K.ALL_MODIFIERS: 2, K.NO_MODIFIER_BONUS: 3, K.OOPS_TWIN: 4, K.BASE_ZERO: 5 }, "order points")

	var plain := [card(C.RED), card(C.BLUE), card(C.GREEN), card(C.YELLOW)]
	var met := func(kind: int, cards: Array, color := -1) -> bool:
		return Scoring.score_potion(cards, SpecialOrder.make(0, kind, 1, color)).order.met
	check(met.call(K.OUTSIDE_COLOR, plain, C.RED), "red on left end")
	check(met.call(K.OUTSIDE_COLOR, plain, C.YELLOW), "yellow on right end")
	check(not met.call(K.OUTSIDE_COLOR, plain, C.BLUE), "blue in the middle doesn't count")
	check(met.call(K.LACKS_COLOR, plain, C.BLACK), "no black")
	check(not met.call(K.LACKS_COLOR, plain, C.RED), "has red")
	var modded := [card(C.RED, 1, M.LEFT, C.RED), card(C.BLUE, 0, M.GLOBAL, C.GREEN), card(C.GREEN, 1, M.RIGHT, C.RED), card(C.BLACK, -1, M.RIGHT, C.RED)]
	check(met.call(K.ALL_MODIFIERS, modded), "all cards have modifiers")
	check(not met.call(K.ALL_MODIFIERS, plain), "plain cards fail all-modifiers")
	check(met.call(K.NO_MODIFIER_BONUS, plain), "no modifier bonus")
	check(not met.call(K.NO_MODIFIER_BONUS, modded), "global green hits the green card")
	var oops_twin := [card(C.BLACK, 0), card(C.RED), card(C.BLACK, -1), card(C.RED)]
	check(met.call(K.OOPS_TWIN, oops_twin), "oops + twin")
	check(not met.call(K.OOPS_TWIN, [card(C.BLACK, 0), card(C.BLACK, 0), card(C.BLACK, 0), card(C.RED)]), "3 black is not a twin")
	check(met.call(K.BASE_ZERO, [card(C.RED), card(C.BLUE), card(C.BLACK, -2), card(C.GREEN, 0, M.GLOBAL, C.RED)]), "base 0")
	check(not met.call(K.BASE_ZERO, plain), "base 4 is not 0")

	var r := Scoring.score_potion(oops_twin, SpecialOrder.make(0, K.OOPS_TWIN, 4))
	check(r.total == 1 + 4 + 4, "met order adds its points: base 1 + oops 4 + order 4 (got %d)" % r.total)
	r = Scoring.score_potion(plain, SpecialOrder.make(0, K.BASE_ZERO, 5))
	check(r.total == 4 + 2 and not r.order.met, "unmet order adds nothing: base 4 + calico 2 (got %d)" % r.total)


func test_order_flow() -> void:
	for n in [2, 3, 4]:
		var gs := GameState.new(n, 3)
		for rnd in Rules.ROUNDS:
			check(gs.phase == GameState.Phase.CHOOSE_ORDER, "round starts with order choice")
			var choosers: Array = []
			while gs.phase == GameState.Phase.CHOOSE_ORDER:
				choosers.append(gs.current_player)
				check(gs.order_offers[gs.current_player].size() == Rules.ORDERS_OFFERED, "offered %d orders" % Rules.ORDERS_OFFERED)
				check(gs.choose_order(gs.current_player, rnd % 2), "choose order")
			check(choosers.size() == n and choosers[0] == gs.first_player, "everyone chooses, first player first (n=%d)" % n)
			check(gs.orders.all(func(o): return o != null), "every player holds an order")
			play_out_round(gs)
			check(gs.last_round_scores.all(func(b): return not b.order.is_empty()), "order scored for every player")
			gs.next_round()
		check(gs.order_deck.size() == 20 - n * Rules.ROUNDS, "kept orders are used up, rejected ones return (n=%d)" % n)


# --- Turn flow ----------------------------------------------------------------

func test_turn_validation() -> void:
	var gs := GameState.new(3, 5)
	var p := gs.current_player
	var other := (p + 1) % 3
	check(not gs.play_card(p, 0, LEFT), "can't play before orders are chosen")
	check(not gs.choose_order(other, 0), "can't choose an order out of turn")
	choose_all_orders(gs)
	check(gs.phase == GameState.Phase.PLAY, "play phase after orders")
	check(not gs.play_card(other, 0, LEFT), "can't play out of turn")
	check(not gs.play_card(p, 99, LEFT), "can't play from a missing deck")
	check(not gs.play_card(p, 0, 7), "can't play to an invalid side")
	check(not gs.skip_swap(p), "can't skip a swap outside the swap phase")
	check(not gs.next_round(), "can't start the next round mid-round")
	check(not gs.apply({ "type": "nonsense", "player": p }), "unknown action rejected")
	var top := gs.top_card(0)
	check(gs.apply({ "type": "play_card", "player": p, "deck": 0, "side": RIGHT }), "apply() plays a card")
	check(gs.potions[p].back() == top, "played card is the deck's former top")


func test_swap() -> void:
	var gs := GameState.new(2, 1)
	choose_all_orders(gs)
	gs.potions[0] = [card(C.RED), card(C.BLACK, -1)]
	gs.potions[1] = [card(C.BLUE), card(C.GREEN), card(C.BLACK, -2)]
	gs.current_player = 0
	gs.phase = GameState.Phase.SWAP
	check(not gs.swap(1, 0, 1, 0, LEFT, LEFT), "can't swap out of turn")
	check(not gs.swap(0, 1, 1, 0, LEFT, LEFT), "can't give a black card")
	check(not gs.swap(0, 0, 1, 2, LEFT, LEFT), "can't take a black card")
	check(not gs.swap(0, 0, 0, 0, LEFT, LEFT), "can't swap with yourself")
	check(gs.swap(0, 0, 1, 1, RIGHT, LEFT), "valid swap")
	check(gs.potions[0].map(func(c): return c.color) == [C.GREEN, C.BLACK], "own potion after swap")
	check(gs.potions[1].map(func(c): return c.color) == [C.BLUE, C.BLACK, C.RED], "other potion after swap")
	check(gs.current_player == 1 and gs.phase == GameState.Phase.PLAY, "turn passes after swap")

	# Swap isn't offered when nobody else has a colour card.
	gs = GameState.new(2, 1)
	choose_all_orders(gs)
	var p := gs.current_player
	gs.potions[p] = [card(C.RED)]
	gs.potions[1 - p] = [card(C.BLACK, -1)]
	gs.middle_decks[0].append(card(C.BLACK, -2))
	gs.play_card(p, 0, LEFT)
	check(gs.phase == GameState.Phase.PLAY and gs.current_player == 1 - p, "swap skipped when impossible")


func test_full_games() -> void:
	for n in [2, 3, 4]:
		var gs := GameState.new(n, 7)
		var firsts: Array = []
		for rnd in Rules.ROUNDS:
			firsts.append(gs.first_player)
			var before := gs.totals.duplicate()
			check(play_out_round(gs) == n * Rules.POTION_SIZE, "each player takes %d turns (n=%d)" % [Rules.POTION_SIZE, n])
			check(gs.potions.all(func(p): return p.size() == Rules.POTION_SIZE), "every potion is full")
			check(gs.last_round_scores.size() == n, "round scored automatically")
			for i in n:
				check(gs.totals[i] == before[i] + gs.last_round_scores[i].total, "totals include the round score")
			gs.next_round()
		check(gs.phase == GameState.Phase.GAME_OVER, "game over after %d rounds" % Rules.ROUNDS)
		check(gs.middle_decks.size() == n + Rules.EXTRA_MIDDLE_DECKS, "n + 1 middle decks")
		var expected: Array = range(Rules.ROUNDS).map(func(i): return i % n)
		check(firsts == expected, "first player rotates (n=%d): %s" % [n, firsts])
		var left: int = gs.middle_decks.reduce(func(a, d): return a + d.size(), 0)
		check(96 - left == n * Rules.POTION_SIZE * Rules.ROUNDS, "used cards are discarded, not refilled")
		check(not gs.winners().is_empty(), "there is a winner")


func test_determinism() -> void:
	var a := GameState.new(4, 1234)
	var b := GameState.new(4, 1234)
	for rnd in Rules.ROUNDS:
		play_out_round(a)
		play_out_round(b)
		a.next_round()
		b.next_round()
	check(a.totals == b.totals, "same seed, same moves, same result")
