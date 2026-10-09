class_name GameState
extends RefCounted
## Authoritative rules engine. Pure data, no nodes, so it can run on a server.
##
## Every player action takes the acting player and returns false if it is illegal
## (wrong phase, not their turn, bad index). `apply()` accepts the same actions as
## plain dictionaries, which is the shape to send over the network.
## All randomness comes from one seeded RNG, so a game replays identically from its seed.
##
## `to_snapshot(player)` gives the JSON-safe state one player is allowed to see;
## `from_snapshot()` rebuilds a GameState from it, with unknown cards as null
## placeholders, so clients and bots can use the same queries without seeing secrets.

enum Phase { CHOOSE_ORDER, PLAY, SWAP, ROUND_OVER, GAME_OVER }
enum Side { LEFT, RIGHT }

const SNAPSHOT_VERSION := 1

var num_players: int
var potions: Array = []          # per player: Array[CardData], left -> right
var totals: Array[int] = []
var middle_decks: Array = []     # Array[Array[CardData]]; the last element is the face-up top
var discard: Array[int] = []     # ids of cards used in finished rounds (they were all face up)
var round_index := 0             # 0-based
var first_player := 0
var current_player := 0          # during CHOOSE_ORDER everyone chooses at once; this is first_player
var phase: Phase = Phase.CHOOSE_ORDER
var last_round_scores: Array = []  # Scoring.score_potion breakdowns, filled when a round ends

# Special orders: each round every player is offered some and keeps one.
# Kept orders leave the deck for good; the rejected ones go back once everyone has chosen.
var order_deck: Array = []       # Array[SpecialOrder]
var order_offers: Array = []     # per player: Array[SpecialOrder] offered this round (empty once chosen)
var orders: Array = []           # per player: the SpecialOrder kept this round (or null)

var _order_returns: Array = []   # per player: offers they turned down this round
var _turns_taken := 0
var _setup := {}
var _rng := RandomNumberGenerator.new()


## `setup` (optional, for the tutorial): { "first_player": int,
##   "decks": [[card spec, ...top first], ...], "offers": [round][player] = [order spec, ...] }.
## num_players == 0 makes an empty shell (used by from_snapshot and clone).
func _init(p_num_players: int, seed := -1, setup := {}) -> void:
	num_players = p_num_players
	if num_players == 0:
		return
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.randomize()
	_setup = setup
	var deck_count := num_players + Rules.EXTRA_MIDDLE_DECKS
	if setup.has("decks"):
		middle_decks = DeckBuilder.deal_fixed(deck_count, setup.decks, _rng)
	else:
		middle_decks = DeckBuilder.deal_middle_decks(deck_count, _rng)
	order_deck = SpecialOrder.build_deck()
	for i in num_players:
		potions.append([])
		totals.append(0)
		order_offers.append([])
		orders.append(null)
		_order_returns.append([])
	first_player = setup.get("first_player", 0)
	_start_round()


# --- Queries ----------------------------------------------------------------

func top_card(deck_idx: int) -> CardData:
	var d: Array = middle_decks[deck_idx]
	return d.back() if not d.is_empty() else null


func can_play(player: int, deck_idx: int) -> bool:
	return phase == Phase.PLAY and player == current_player \
		and deck_idx >= 0 and deck_idx < middle_decks.size() \
		and not middle_decks[deck_idx].is_empty() \
		and potions[player].size() < Rules.POTION_SIZE


func is_swappable(player: int, idx: int) -> bool:
	return player >= 0 and player < num_players \
		and idx >= 0 and idx < potions[player].size() and not potions[player][idx].is_black()


## True if `player` has a colour card and some other player does too.
func swap_possible(player: int) -> bool:
	if not _has_color_card(potions[player]):
		return false
	for i in num_players:
		if i != player and _has_color_card(potions[i]):
			return true
	return false


func needs_order(player: int) -> bool:
	return phase == Phase.CHOOSE_ORDER and player >= 0 and player < num_players \
		and not order_offers[player].is_empty()


func players_needing_order() -> Array[int]:
	var out: Array[int] = []
	for i in num_players:
		if needs_order(i):
			out.append(i)
	return out


## Every legal action for `player` right now, as apply() dictionaries. Moves that
## would give the same result (both sides of an empty potion) are listed once.
func legal_actions(player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match phase:
		Phase.CHOOSE_ORDER:
			if needs_order(player):
				for i in order_offers[player].size():
					out.append({ "type": "choose_order", "player": player, "offer": i })
		Phase.PLAY:
			for d in middle_decks.size():
				if can_play(player, d):
					for side in _sides(potions[player].size()):
						out.append({ "type": "play_card", "player": player, "deck": d, "side": side })
		Phase.SWAP:
			if player != current_player:
				return out
			out.append({ "type": "skip_swap", "player": player })
			for own in potions[player].size():
				if not is_swappable(player, own):
					continue
				for other in num_players:
					if other == player:
						continue
					for idx in potions[other].size():
						if not is_swappable(other, idx):
							continue
						for other_side in _sides(potions[other].size() - 1):
							for own_side in _sides(potions[player].size() - 1):
								out.append({ "type": "swap", "player": player, "own": own, "other_player": other,
									"other": idx, "other_side": other_side, "own_side": own_side })
	return out


func winners() -> Array[int]:
	var best: int = totals.max()
	var out: Array[int] = []
	for i in num_players:
		if totals[i] == best:
			out.append(i)
	return out


# --- Actions ----------------------------------------------------------------

## Network-friendly entry point, e.g. {"type": "play_card", "player": 0, "deck": 2, "side": 1}.
## Numbers may arrive as floats (JSON), so every field is cast.
func apply(action: Dictionary) -> bool:
	var p := int(action.get("player", -1))
	match action.get("type", ""):
		"choose_order":
			return choose_order(p, int(action.get("offer", -1)))
		"play_card":
			return play_card(p, int(action.get("deck", -1)), int(action.get("side", -1)))
		"swap":
			return swap(p, int(action.get("own", -1)), int(action.get("other_player", -1)),
				int(action.get("other", -1)), int(action.get("other_side", -1)), int(action.get("own_side", -1)))
		"skip_swap":
			return skip_swap(p)
	return false


## Players choose at the same time; drafting starts once everyone has an order.
func choose_order(player: int, offer_idx: int) -> bool:
	if not needs_order(player):
		return false
	var offer: Array = order_offers[player]
	if offer_idx < 0 or offer_idx >= offer.size():
		return false
	orders[player] = offer[offer_idx]
	var returned: Array = []
	for k in offer.size():
		if k != offer_idx:
			returned.append(offer[k])
	_order_returns[player] = returned
	order_offers[player] = []
	_maybe_finish_order_choice()
	return true


## Takes the top card of a middle deck and puts it on one end of the player's potion.
## A black card then opens the optional swap (if any swap is possible).
func play_card(player: int, deck_idx: int, side: int) -> bool:
	if not can_play(player, deck_idx) or not _valid_side(side):
		return false
	var card: CardData = middle_decks[deck_idx].pop_back()
	_insert(potions[player], card, side)
	if card.is_black() and swap_possible(player):
		phase = Phase.SWAP
	else:
		_end_turn()
	return true


## Swaps the player's colour card at own_idx with other_player's colour card at other_idx.
## The given card lands on `other_side` of the other potion; the taken card on `own_side` of the player's.
func swap(player: int, own_idx: int, other_player: int, other_idx: int, other_side: int, own_side: int) -> bool:
	if phase != Phase.SWAP or player != current_player or other_player == player:
		return false
	if not is_swappable(player, own_idx) or not is_swappable(other_player, other_idx):
		return false
	if not _valid_side(other_side) or not _valid_side(own_side):
		return false
	var mine: Array = potions[player]
	var theirs: Array = potions[other_player]
	var given: CardData = mine.pop_at(own_idx)
	var taken: CardData = theirs.pop_at(other_idx)
	_insert(theirs, given, other_side)
	_insert(mine, taken, own_side)
	_end_turn()
	return true


func skip_swap(player: int) -> bool:
	if phase != Phase.SWAP or player != current_player:
		return false
	_end_turn()
	return true


## Host-side: discards the potions and starts the next round (or ends the game).
## Called once clients have finished showing the round's scores.
func next_round() -> bool:
	if phase != Phase.ROUND_OVER:
		return false
	for p in potions:
		for c in p:
			if c:
				discard.append(c.id)
		p.clear()
	round_index += 1
	if round_index >= Rules.ROUNDS:
		phase = Phase.GAME_OVER
		return true
	first_player = (first_player + 1) % num_players
	_start_round()
	return true


# --- Snapshots ----------------------------------------------------------------

## The action as `for_player` may see it: which order someone else kept stays secret.
static func redact_action(action: Dictionary, for_player: int) -> Dictionary:
	if action.get("type") == "choose_order" and int(action.get("player", -1)) != for_player:
		return { "type": "choose_order", "player": action.player }
	return action


## JSON-safe state. for_player == -1 is everything (server-side, debugging, saving);
## otherwise only what that player may see: deck tops, not the cards below; their own
## offers but only a count of others'; others' orders only once the round is scored;
## never the RNG. Cards are [id, color, value, modifier, modifier_color], orders [id, kind, points, color].
func to_snapshot(for_player := -1) -> Dictionary:
	var full := for_player < 0
	var revealed := phase == Phase.ROUND_OVER or phase == Phase.GAME_OVER
	var decks: Array = []
	for deck in middle_decks:
		if full:
			decks.append({ "n": deck.size(), "cards": deck.map(_card_arr) })
		else:
			decks.append({ "n": deck.size(), "top": _card_arr(deck.back()) if not deck.is_empty() else null })
	var offers: Array = []
	var kept: Array = []
	for i in num_players:
		var mine := full or i == for_player
		offers.append(order_offers[i].map(_order_arr) if mine else order_offers[i].size())
		var o: SpecialOrder = orders[i]
		if o == null:
			kept.append(null)
		elif mine or revealed:
			kept.append(_order_arr(o))
		else:
			kept.append(true)
	var d := {
		"v": SNAPSHOT_VERSION,
		"you": for_player,
		"n": num_players,
		"phase": phase,
		"round": round_index,
		"first": first_player,
		"current": current_player,
		"turns": _turns_taken,
		"totals": totals.duplicate(),
		"potions": potions.map(func(p): return p.map(_card_arr)),
		"decks": decks,
		"discard": discard.duplicate(),
		"offers": offers,
		"orders": kept,
		"order_deck": order_deck.map(_order_arr) if full else order_deck.size(),
		"scores": last_round_scores.duplicate(true) if revealed else [],
	}
	if full:
		d["returns"] = _order_returns.map(func(r): return r.map(_order_arr))
		d["setup"] = _setup.duplicate(true)
		# Strings: JSON numbers are doubles and would lose the low bits of a 64-bit seed.
		d["rng"] = { "seed": str(_rng.seed), "state": str(_rng.state) }
	return d


static func from_snapshot(d: Dictionary) -> GameState:
	var gs := GameState.new(0)
	gs.num_players = int(d.n)
	gs.phase = int(d.phase)
	gs.round_index = int(d.round)
	gs.first_player = int(d.first)
	gs.current_player = int(d.current)
	gs._turns_taken = int(d.turns)
	for t in d.totals:
		gs.totals.append(int(t))
	for p in d.potions:
		gs.potions.append(p.map(CardData.from_array))
	for deck in d.decks:
		var cards: Array = []
		if deck.has("cards"):
			cards = deck.cards.map(CardData.from_array)
		else:
			cards.resize(int(deck.n))   # unknown cards stay null
			if deck.get("top") != null:
				cards[cards.size() - 1] = CardData.from_array(deck.top)
		gs.middle_decks.append(cards)
	for id in d.discard:
		gs.discard.append(int(id))
	for o in d.offers:
		if o is Array:
			gs.order_offers.append(o.map(SpecialOrder.from_array))
		else:
			var hidden: Array = []
			hidden.resize(int(o))
			gs.order_offers.append(hidden)
	for o in d.orders:
		if o is Array:
			gs.orders.append(SpecialOrder.from_array(o))
		elif o == null:
			gs.orders.append(null)
		else:
			gs.orders.append(SpecialOrder.hidden())
	if d.order_deck is Array:
		gs.order_deck = d.order_deck.map(SpecialOrder.from_array)
	else:
		gs.order_deck.resize(int(d.order_deck))
	for b in d.scores:
		gs.last_round_scores.append(_score_from(b))
	if d.has("returns"):
		for r in d.returns:
			gs._order_returns.append(r.map(SpecialOrder.from_array))
	else:
		for i in gs.num_players:
			gs._order_returns.append([])
	gs._setup = d.get("setup", {})
	if d.has("rng"):
		gs._rng.seed = int(d.rng.seed)
		gs._rng.state = int(d.rng.state)
	return gs


## Copy for lookahead: arrays are copied, CardData/SpecialOrder objects are shared
## (they are never mutated).
func clone() -> GameState:
	var gs := GameState.new(0)
	gs.num_players = num_players
	gs.potions = potions.map(func(p): return p.duplicate())
	gs.totals = totals.duplicate()
	gs.middle_decks = middle_decks.map(func(m): return m.duplicate())
	gs.discard = discard.duplicate()
	gs.round_index = round_index
	gs.first_player = first_player
	gs.current_player = current_player
	gs.phase = phase
	gs.last_round_scores = last_round_scores.duplicate()
	gs.order_deck = order_deck.duplicate()
	gs.order_offers = order_offers.map(func(o): return o.duplicate())
	gs.orders = orders.duplicate()
	gs._order_returns = _order_returns.map(func(r): return r.duplicate())
	gs._turns_taken = _turns_taken
	gs._setup = _setup
	gs._rng.seed = _rng.seed
	gs._rng.state = _rng.state
	return gs


## Reseeds the RNG (lookahead copies must not reuse the real game's future draws).
func reseed(seed: int) -> void:
	_rng.seed = seed


# --- Internals --------------------------------------------------------------

func _start_round() -> void:
	_turns_taken = 0
	current_player = first_player
	_deal_orders()


## Deals offers to every player at once (late rounds may need the last orders in the deck).
## Scripted setups name the offers for the first rounds.
func _deal_orders() -> void:
	var scripted: Array = []
	var all_scripted: Array = _setup.get("offers", [])
	if round_index < all_scripted.size():
		scripted = all_scripted[round_index]
	for i in num_players:
		orders[i] = null
		_order_returns[i] = []
		var offer: Array = []
		if i < scripted.size():
			for spec in scripted[i]:
				var o := _take_order(spec)
				if o:
					offer.append(o)
		else:
			for k in Rules.ORDERS_OFFERED:
				if order_deck.is_empty():
					break
				offer.append(order_deck.pop_at(_rng.randi_range(0, order_deck.size() - 1)))
		order_offers[i] = offer
	phase = Phase.CHOOSE_ORDER
	current_player = first_player
	_maybe_finish_order_choice()


func _take_order(spec: String) -> SpecialOrder:
	var want := SpecialOrder.parse_spec(spec)
	for k in order_deck.size():
		var o: SpecialOrder = order_deck[k]
		if not want.is_empty() and o.kind == want[0] and o.color == want[1]:
			return order_deck.pop_at(k)
	push_error("GameState: no special order left for spec '%s'" % spec)
	return null


## Once nobody has offers left, turned-down orders go back (in seat order, so the
## result doesn't depend on who chose first) and drafting starts.
func _maybe_finish_order_choice() -> void:
	if not players_needing_order().is_empty():
		return
	for i in num_players:
		order_deck.append_array(_order_returns[i])
		_order_returns[i] = []
	current_player = first_player
	phase = Phase.PLAY


func _end_turn() -> void:
	_turns_taken += 1
	if _turns_taken >= num_players * Rules.POTION_SIZE:
		_score_round()
		return
	current_player = (current_player + 1) % num_players
	phase = Phase.PLAY


func _score_round() -> void:
	last_round_scores.clear()
	for i in num_players:
		var o: SpecialOrder = orders[i]
		var b := Scoring.score_potion(potions[i], o if o and not o.is_hidden() else null)
		totals[i] += b.total
		last_round_scores.append(b)
	phase = Phase.ROUND_OVER


static func _insert(potion: Array, card: CardData, side: int) -> void:
	if side == Side.LEFT:
		potion.push_front(card)
	else:
		potion.push_back(card)


static func _valid_side(side: int) -> bool:
	return side == Side.LEFT or side == Side.RIGHT


## Both sides give the same result when the potion is empty.
static func _sides(potion_size: int) -> Array:
	return [Side.LEFT] if potion_size == 0 else [Side.LEFT, Side.RIGHT]


static func _has_color_card(potion: Array) -> bool:
	return potion.any(func(c): return not c.is_black())


static func _card_arr(c: CardData):
	return c.to_array() if c else null


static func _order_arr(o: SpecialOrder):
	return o.to_array() if o else null


## Scoring breakdowns come back from JSON with float numbers; make them ints again.
static func _score_from(b: Dictionary) -> Dictionary:
	var out := {
		"base": b.base.map(func(x): return int(x)),
		"mod_hits": b.mod_hits.map(func(h): return { "src": int(h.src), "dst": int(h.dst), "pts": int(h.pts) }),
		"bonus": { "name": str(b.bonus.name), "pts": int(b.bonus.pts) },
		"order": {},
		"total": int(b.total),
	}
	if not b.order.is_empty():
		out.order = { "title": str(b.order.title), "pts": int(b.order.pts), "met": bool(b.order.met) }
	return out
