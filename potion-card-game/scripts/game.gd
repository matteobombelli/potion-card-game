extends TableRoot
## Game controller: drives the local player's seat against a Match (CPUs or the
## server), turns clicks into rules actions and plays the animations.
##
## Flow: _advance() looks at the (redacted) state and sets up the next step. On
## your turn each step builds a list of clickable `targets`; a click calls the
## handler for its kind. Nothing is sent until a move is complete (a card placed,
## a swap finished), so a held card can still be put back. Moves by everyone else
## arrive as Match events; they queue up and are animated one at a time. Views
## mirror the state; _resync() rebuilds them if they ever disagree.

enum Mode { NONE, WAIT, CHOOSE_ORDER, PICK, PLACE, SWAP_OWN, SWAP_OTHER, SWAP_PLACE_OTHER, SWAP_PLACE_OWN }

signal _echo

const MAIN_MENU := "res://scenes/main_menu.tscn"
const LOBBY := "res://scenes/lobby.tscn"
const CPU_NAMES := ["CPU 1", "CPU 2", "CPU 3"]

var game_match: Match
var state: GameState        # what the local player can see; rebuilt from every snapshot
var me := 0
var director: TutorialDirector
var decks: Array[MiddleDeckView] = []
var potions: Array[PotionView] = []   # indexed by player, not by seat
var hud := Hud.new()

var busy := true            # animating: input is ignored
var mode := Mode.NONE
var targets: Array = []     # [{ node, kind, data }] that can be clicked right now
var _hovered = null         # the `targets` entry under the mouse

# The move being built.
var _held: CardView          # card following the player before it's placed
var _held_from := -1         # middle deck it came from
var _held_potion: PotionView # potion its drop slots are shown on
var _swap := {}              # own_idx, own_view, other_player, other_idx, other_view, other_side
var _order_overlay: OrderChoiceOverlay
var _game_over: GameOverOverlay
var _time := 0.0

# Events from the game_match.
var _events: Array = []      # [{ action, snapshot }] waiting to be animated
var _pumping := false
var _awaiting := {}          # our own submitted action, until the match echoes it
var _echo_snapshot := {}
var _was_rejected := false
var _seq := -1               # newest snapshot adopted
var _scored_round := -1      # round whose scores have been shown


func _ready() -> void:
	hud.skip_pressed.connect(skip_swap)
	hud.leave_confirmed.connect(_leave)
	add_child(hud)
	game_match = _make_match()
	add_child(game_match)
	game_match.event.connect(_on_event)
	game_match.rejected.connect(_on_rejected)
	game_match.seats_changed.connect(_refresh_names)
	game_match.room_changed.connect(_on_room_changed)
	game_match.closed.connect(_on_closed)
	game_match.started.connect(_on_started, CONNECT_ONE_SHOT)
	game_match.begin()


func _make_match() -> Match:
	match Session.mode:
		Session.Mode.TUTORIAL:
			var gs := GameState.new(2, TutorialScript.SEED, TutorialScript.setup())
			var bot := ScriptedBot.new(TutorialScript.cpu_actions(), Bot.create(Bot.Difficulty.EASY))
			var lm := LocalMatch.new(gs, { 1: bot }, ["YOU", "CPU"] as Array[String])
			director = TutorialDirector.new(self, lm)
			add_child(director)
			hud.leave_text = "Leave the tutorial?"
			return lm
		Session.Mode.ONLINE:
			hud.leave_text = "Leave the game? A CPU will take your seat."
			return NetMatch.new(Session.online_start)
	var n := clampi(Session.num_players, 2, 4)
	var bots := {}
	var names: Array[String] = ["YOU"]
	for i in range(1, n):
		bots[i] = Bot.create(Session.difficulty)
		names.append(CPU_NAMES[i - 1])
	return LocalMatch.new(GameState.new(n), bots, names)


func _on_started(snapshot: Dictionary) -> void:
	me = game_match.local_player
	_adopt(snapshot)
	_build_board()
	hud.set_round(state.round_index, Rules.ROUNDS)
	if state.round_index == 0 and state.potions.all(func(p): return p.is_empty()):
		await _deal()
		await Fx.banner("ROUND 1", Palette.TITLE, 0.5)
	else:
		_resync()   # joining a game already under way
	_advance()


func _build_board() -> void:
	var n := state.num_players
	var seats := TableLayout.seats(n)
	for i in n:
		var seat: Dictionary = seats[TableLayout.seat_of(i, me, n)]
		var pv := PotionView.new()
		pv.position = seat.position
		board_layer.add_child(pv)
		pv.setup(i, seat.top, name_of(i))
		potions.append(pv)
	for pos in TableLayout.deck_positions(state.middle_decks.size()):
		var d := MiddleDeckView.new()
		d.position = pos
		board_layer.add_child(d)
		decks.append(d)


func name_of(p: int) -> String:
	if p == me:
		return "YOU"
	return game_match.seat_names[p] if p < game_match.seat_names.size() else "PLAYER %d" % (p + 1)


func _refresh_names() -> void:
	for i in potions.size():
		potions[i].set_player_name(name_of(i))


## Card backs fly in from above and stack up on the middle decks, then the tops flip.
func _deal() -> void:
	var n := decks.size()
	var remaining: Array[int] = []
	for d in state.middle_decks:
		remaining.append(d.size())
	var back := CardArt.make_material(CardArt.BACK_TINT)
	var i := 0
	while remaining.any(func(r): return r > 0):
		var d := i % n
		i += 1
		if remaining[d] == 0:
			continue
		remaining[d] -= 1
		var deck := decks[d]
		var s := Sprite2D.new()
		s.texture = CardArt.BACKING
		s.material = back
		s.scale = Vector2.ONE * CardArt.SCALE
		s.position = Vector2(TableLayout.CENTER.x + randf_range(-120, 120), -140)
		s.rotation = randf_range(-1.5, 1.5)
		cards_layer.add_child(s)
		var t := s.create_tween().set_parallel()
		t.tween_property(s, "position", deck.position, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(s, "rotation", randf_range(-0.05, 0.05), 0.32)
		t.chain().tween_callback(func():
			deck.set_contents(deck.count + 1, null, false)
			s.queue_free())
		await get_tree().create_timer(0.016).timeout
	await get_tree().create_timer(0.45).timeout
	for d in n:
		decks[d].set_contents(state.middle_decks[d].size(), state.top_card(d))
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.3).timeout


# --- Flow -------------------------------------------------------------------

## Sets up whatever the game is waiting for next. Safe to call repeatedly.
func _advance() -> void:
	if not _events.is_empty():
		_pump()
		return
	busy = false
	_clear_targets()
	_check_sync()
	for pv in potions:
		pv.set_thinking(false)
	match state.phase:
		GameState.Phase.CHOOSE_ORDER:
			if state.needs_order(me):
				_begin_order_choice()
			else:
				_wait_for_orders()
		GameState.Phase.PLAY:
			if state.current_player == me:
				_begin_pick()
			else:
				_wait_for_turn()
		GameState.Phase.SWAP:
			if state.current_player == me:
				_begin_swap()
			else:
				_wait_for_turn()
		GameState.Phase.ROUND_OVER:
			_play_round_end()
		GameState.Phase.GAME_OVER:
			_show_game_over()


func _set_active(player: int) -> void:
	for i in potions.size():
		potions[i].set_active(i == player)


func _wait_for_turn() -> void:
	mode = Mode.WAIT
	var p := state.current_player
	_set_active(p)
	potions[p].set_thinking(true)
	var verb := "is deciding whether to swap" if state.phase == GameState.Phase.SWAP else "is choosing a card"
	hud.set_turn("%s'S TURN" % name_of(p).to_upper(), "%s %s." % [name_of(p), verb])
	if director:
		director.before_step("wait")


func _wait_for_orders() -> void:
	mode = Mode.WAIT
	_set_active(-1)
	var waiting: Array = Array(state.players_needing_order()).map(name_of)
	for p in state.players_needing_order():
		potions[p].set_thinking(true)
	hud.set_turn("SPECIAL ORDERS", "Waiting for %s to choose." % ", ".join(waiting))


# --- Events from the match ----------------------------------------------------

func _on_event(action: Dictionary, snapshot: Dictionary) -> void:
	if not _awaiting.is_empty() and int(action.get("player", -1)) == me and action.type == _awaiting.type:
		_echo_snapshot = snapshot
		_awaiting = {}
		_echo.emit()
		return
	_events.append({ "action": action, "snapshot": snapshot })
	if _can_pump():
		_pump()


func _on_rejected(snapshot: Dictionary) -> void:
	_echo_snapshot = snapshot
	_was_rejected = true
	_awaiting = {}
	_echo.emit()


## Others' moves are only shown while we're not in the middle of our own.
func _can_pump() -> bool:
	return not busy and not _pumping and _awaiting.is_empty() \
		and (mode == Mode.NONE or mode == Mode.WAIT or mode == Mode.CHOOSE_ORDER) \
		and _game_over == null


func _pump() -> void:
	if _pumping:
		return
	_pumping = true
	busy = true
	while not _events.is_empty():
		var e: Dictionary = _events.pop_front()
		await _present(e.action, e.snapshot)
		_adopt(e.snapshot)
		if director:
			await director.after_event(e.action)
	_pumping = false
	busy = false
	_advance()


## Takes a snapshot as the new state unless a newer one is already in.
func _adopt(snapshot: Dictionary) -> void:
	var seq := int(snapshot.get("seq", _seq + 1))
	if seq <= _seq:
		return
	_seq = seq
	state = GameState.from_snapshot(snapshot)


## Sends our completed move. Call _finish_commit() to wait for the match's answer.
func _commit(action: Dictionary) -> void:
	_was_rejected = false
	_echo_snapshot = {}
	_awaiting = action
	game_match.submit(action)


## Waits for our move to be echoed (instant offline). Returns false if it was rejected,
## in which case the views have been rebuilt from the real state.
func _finish_commit() -> bool:
	while not _awaiting.is_empty():
		await _echo
	_adopt(_echo_snapshot)
	if _was_rejected:
		push_warning("Move rejected; rebuilding from the real state")
		_resync()
		return false
	return true


## Animates a move by another player (or the start of a new round).
func _present(action: Dictionary, snapshot: Dictionary) -> void:
	var p := int(action.get("player", -1))
	match action.type:
		"choose_order":
			if p != me:
				potions[p].set_thinking(false)
				potions[p].set_order_hidden()
		"play_card":
			var d := int(action.deck)
			var pv := potions[p]
			var v := decks[d].lift_top(cards_layer) if decks[d].top_view else null
			var next := GameState.from_snapshot(snapshot)
			decks[d].set_contents(next.middle_decks[d].size(), next.top_card(d))
			if v == null:
				return   # views were out of sync; _check_sync will rebuild them
			pv.set_thinking(false)
			v.z_index = 10
			await v.fly_to(pv.held_position(), 0.38, -160.0).finished
			await get_tree().create_timer(0.15).timeout
			await v.slam_to(pv.insert(v, int(action.side)))
			v.z_index = 0
			pv.layout(0.35)
		"swap":
			var other := int(action.other_player)
			var a := potions[p].cards[int(action.own)]
			var b := potions[other].cards[int(action.other)]
			hud.set_prompt("%s swaps with %s!" % [name_of(p), name_of(other)])
			await _anim_cross(potions[p], a, potions[other], b)
			await _anim_land(a, potions[other], int(action.other_side))
			await _anim_land(b, potions[p], int(action.own_side))
		"skip_swap":
			potions[p].set_thinking(false)
			Fx.float_text(potions[p].held_position(), "NO SWAP", Palette.TEXT_DIM, 34)
			await get_tree().create_timer(0.35).timeout
		"next_round":
			var next := GameState.from_snapshot(snapshot)
			if next.phase != GameState.Phase.GAME_OVER:
				hud.set_round(next.round_index, Rules.ROUNDS)
				var last := next.round_index == Rules.ROUNDS - 1
				await Fx.banner("FINAL ROUND" if last else "ROUND %d" % (next.round_index + 1), Palette.TITLE, 0.5)


# --- Special order choice ---------------------------------------------------

func _begin_order_choice() -> void:
	mode = Mode.CHOOSE_ORDER
	_set_active(-1)
	var others: Array = Array(state.players_needing_order()).filter(func(p): return p != me)
	for p in others:
		potions[p].set_thinking(true)
	hud.set_turn("YOUR ORDER", "Choose your special order for this round.")
	if _order_overlay:
		return
	var allowed := director.allowed_order() if director else -1
	_order_overlay = OrderChoiceOverlay.new("CHOOSE A SPECIAL ORDER", state.order_offers[me], allowed)
	_order_overlay.chosen.connect(choose_order)
	add_child(_order_overlay)
	if director:
		director.before_step("order")


## Public so tests can drive it; the overlay calls it on click.
func choose_order(offer_idx: int) -> void:
	if mode != Mode.CHOOSE_ORDER or offer_idx < 0 or offer_idx >= state.order_offers[me].size():
		return
	if busy:   # another player's move is being shown; let the overlay take the click again
		if _order_overlay:
			_order_overlay.unlock()
		return
	if director and director.allowed_order() >= 0 and offer_idx != director.allowed_order():
		return
	busy = true
	potions[me].set_order(state.order_offers[me][offer_idx])
	_order_overlay.close()
	_order_overlay = null
	if director:
		director.step_done()
	_commit({ "type": "choose_order", "player": me, "offer": offer_idx })
	await _finish_commit()
	await get_tree().create_timer(0.25).timeout
	mode = Mode.NONE
	_advance()


# --- Taking and placing a card ----------------------------------------------

func _begin_pick() -> void:
	mode = Mode.PICK
	_set_active(me)
	hud.set_turn("YOUR TURN", "Take the top card of any middle deck.")
	for i in decks.size():
		if state.can_play(me, i) and decks[i].top_view:
			_add_target(decks[i].top_view, "deck", i, Palette.TARGET)
	if director:
		director.before_step("pick")


func _pick_up(deck_idx: int) -> void:
	busy = true
	_clear_targets()
	if director:
		director.step_done()
	_held = decks[deck_idx].lift_top(cards_layer)
	_held.z_index = 10
	_held_from = deck_idx
	var potion := potions[me]
	await _held.fly_to(potion.held_position(), 0.38, -160.0).finished
	mode = Mode.PLACE
	_add_target(_held, "held", null)   # added before the slots so the slots win where they overlap
	_offer_slots(potion, "Place it on the left or right end of your potion. Click the card to put it back.")
	busy = false
	if director:
		director.before_step("place")


func _put_back() -> void:
	busy = true
	_clear_targets()
	_held_potion.show_ghosts(false)
	var v := _held
	_held = null
	await v.fly_to(decks[_held_from].global_position, 0.3, -100.0).finished
	v.z_index = 0
	decks[_held_from].put_back(v)
	mode = Mode.NONE
	_advance()


func _place(side: int) -> void:
	busy = true
	_clear_targets()
	_held_potion.show_ghosts(false)
	if director:
		director.step_done()
	var v := _held
	_held = null
	_commit({ "type": "play_card", "player": me, "deck": _held_from, "side": side })
	if not await _finish_commit():
		mode = Mode.NONE
		_advance()
		return
	decks[_held_from].set_contents(state.middle_decks[_held_from].size(), state.top_card(_held_from))
	await v.slam_to(potions[me].insert(v, side))
	v.z_index = 0
	potions[me].layout(0.35)
	mode = Mode.NONE
	_advance()


## Shows drop slots on `potion` for the held card.
func _offer_slots(potion: PotionView, prompt: String) -> void:
	_held_potion = potion
	potion.show_ghosts(true)
	for g in potion.ghosts():
		_add_target(g, "slot", g.side)
	hud.set_prompt(prompt)


# --- Black card swap ----------------------------------------------------------

func _begin_swap() -> void:
	mode = Mode.SWAP_OWN
	_swap = {}
	_set_active(me)
	hud.set_turn("YOUR TURN", "")
	hud.show_skip(director == null or director.allows_skip())
	hud.set_prompt("Black card! You may swap one of your colour cards with another player's. Pick your card, or skip.")
	for i in potions[me].cards.size():
		if state.is_swappable(me, i):
			_add_target(potions[me].cards[i], "own_card", i, Palette.SWAP)
	if director:
		director.before_step("swap_own")


func _select_own(idx: int) -> void:
	var v := potions[me].cards[idx]
	var previous: CardView = _swap.get("own_view")
	_clear_targets()
	if previous:
		previous.set_selected(false)
	if previous == v:   # clicking the selected card again deselects it
		_begin_swap()
		return
	if director:
		director.step_done()
	_swap = { "own_idx": idx, "own_view": v }
	v.set_selected(true)
	mode = Mode.SWAP_OTHER
	hud.set_prompt("Now pick another player's colour card to take. (Click your card again to change.)")
	for i in potions[me].cards.size():
		if state.is_swappable(me, i):
			_add_target(potions[me].cards[i], "own_card", i, Color.WHITE if i == idx else Palette.SWAP)
	for other in potions.size():
		if other == me:
			continue
		for i in potions[other].cards.size():
			if state.is_swappable(other, i):
				_add_target(potions[other].cards[i], "other_card", [other, i], Palette.TARGET)
	if director:
		director.before_step("swap_other")


## Both cards leave their potions and cross over, then each gets placed.
func _select_other(other: int, idx: int) -> void:
	busy = true
	_clear_targets()
	hud.show_skip(false)
	if director:
		director.step_done()
	var theirs := potions[other]
	var a: CardView = _swap.own_view
	var b := theirs.cards[idx]
	_swap.merge({ "other_player": other, "other_idx": idx, "other_view": b })
	a.set_selected(false)
	await _anim_cross(potions[me], a, theirs, b)
	_held = a
	mode = Mode.SWAP_PLACE_OTHER
	_offer_slots(theirs, "Choose where your card goes in %s's potion." % name_of(other))
	busy = false
	if director:
		director.before_step("swap_place_other")


func _place_swap(side: int) -> void:
	busy = true
	_clear_targets()
	_held_potion.show_ghosts(false)
	if director:
		director.step_done()
	var v := _held
	_held = null
	if mode == Mode.SWAP_PLACE_OTHER:
		_swap.other_side = side
		await _anim_land(v, _held_potion, side)
		_held = _swap.other_view
		mode = Mode.SWAP_PLACE_OWN
		_offer_slots(potions[me], "Choose where your new card goes in your potion.")
		busy = false
		if director:
			director.before_step("swap_place_own")
		return

	# Both ends chosen: send the swap, then land the last card.
	_commit({ "type": "swap", "player": me, "own": _swap.own_idx, "other_player": _swap.other_player,
		"other": _swap.other_idx, "other_side": _swap.other_side, "own_side": side })
	var ok := await _finish_commit()
	_swap = {}
	if ok:
		await _anim_land(v, potions[me], side)
	mode = Mode.NONE
	_advance()


## Public so tests can drive it; the HUD button calls it.
func skip_swap() -> void:
	if busy or not (mode == Mode.SWAP_OWN or mode == Mode.SWAP_OTHER):
		return
	if director and not director.allows_skip():
		return
	busy = true
	if _swap.has("own_view"):
		_swap.own_view.set_selected(false)
	_swap = {}
	hud.show_skip(false)
	_clear_targets()
	_commit({ "type": "skip_swap", "player": me })
	await _finish_commit()
	mode = Mode.NONE
	_advance()


## Two cards leave their potions and fly past each other to the other potion.
func _anim_cross(pa: PotionView, a: CardView, pb: PotionView, b: CardView) -> void:
	pa.cards.erase(a)
	pb.cards.erase(b)
	pa.layout(0.35)
	pb.layout(0.35)
	a.z_index = 10
	b.z_index = 10
	var trails := [Fx.trail(a, CardArt.fx_color(a.card.color)), Fx.trail(b, CardArt.fx_color(b.card.color))]
	await get_tree().create_timer(0.12).timeout
	a.fly_to(pb.held_position(), 0.55, -260.0, TAU)
	await b.fly_to(pa.held_position(), 0.55, 260.0, -TAU).finished
	for t in trails:
		Fx.stop_trail(t)


func _anim_land(v: CardView, pv: PotionView, side: int) -> void:
	await v.slam_to(pv.insert(v, side))
	v.z_index = 0
	pv.layout(0.35)


# --- Round end and game over ------------------------------------------------

func _play_round_end() -> void:
	if _scored_round == state.round_index:
		mode = Mode.WAIT
		hud.set_turn("SCORING", "Waiting for the other players...")
		return
	_scored_round = state.round_index
	busy = true
	mode = Mode.NONE
	_set_active(-1)
	hud.set_turn("SCORING", "Every potion is complete. Let's see what you brewed!")
	for p in potions.size():   # secret orders are revealed
		if state.orders[p] and potions[p].has_hidden_order():
			potions[p].reveal_order(state.orders[p])
	await get_tree().create_timer(0.6).timeout
	var n := potions.size()
	for k in n:
		var p := (me + k) % n   # your potion first
		potions[p].set_active(true)
		var hook := director.score_hook(p) if director else Callable()
		await ScoreSequence.run(potions[p], state.last_round_scores[p], hook)
		potions[p].set_total(state.totals[p])
		await get_tree().create_timer(0.5).timeout
		potions[p].set_active(false)
	await get_tree().create_timer(0.6).timeout
	await _sweep_cards()
	for pv in potions:
		pv.hide_round_score()
		pv.set_order(null)
	if director:
		await director.before_next_round(state.round_index)
	busy = false
	mode = Mode.WAIT
	hud.set_turn("SCORING", "Waiting for the other players...")
	game_match.scores_shown()   # the next round arrives as a "next_round" event


## Used cards spin off the table.
func _sweep_cards() -> void:
	var last: Tween
	for pv in potions:
		var dir := pv.toward_center() * -700.0
		for v in pv.cards:
			last = v.move_tween().set_parallel()
			last.tween_property(v, "global_position", v.global_position + dir + Vector2(randf_range(-260, 260), 0), 0.6) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			last.tween_property(v, "rotation", randf_range(-2.5, 2.5), 0.6)
			last.chain().tween_callback(v.queue_free)
			await get_tree().create_timer(0.05).timeout
		pv.cards.clear()
	if last:
		await last.finished


func _show_game_over() -> void:
	if _game_over:
		return
	busy = true
	mode = Mode.NONE
	_set_active(-1)
	hud.clear()
	hud.show_menu_button(false)
	if Session.mode == Session.Mode.TUTORIAL:
		Session.tutorial_done = true
		Session.save()
	for d in decks:   # leftover middle decks tumble off the table
		var t := d.create_tween().set_parallel()
		t.tween_property(d, "position", d.position + Vector2(randf_range(-150, 150), 800), 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(d, "rotation", randf_range(-1.5, 1.5), 0.6)
	var names: Array = range(state.num_players).map(name_of)
	_game_over = GameOverOverlay.new(state.totals, state.winners(), names, me, Session.mode)
	_game_over.play_again.connect(func(): get_tree().reload_current_scene())
	_game_over.play_cpu.connect(func():
		Session.mode = Session.Mode.CPU
		get_tree().reload_current_scene())
	_game_over.main_menu.connect(_leave)
	_game_over.rematch.connect(func(ready: bool): Net.send("rematch", { "ready": ready }))
	add_child(_game_over)
	if game_match is NetMatch:
		_on_room_changed(Net.room)


func _on_room_changed(room: Dictionary) -> void:
	if _game_over == null or room.is_empty():
		return
	var members: Array = room.get("members", [])
	var ready := members.filter(func(m): return m.get("rematch", false)).size()
	_game_over.set_rematch_votes(ready, members.size(), members.size() < state.num_players)


func _on_closed(reason: String) -> void:
	busy = true
	hud.set_turn("DISCONNECTED", reason)
	await Fx.banner("DISCONNECTED", Palette.NEGATIVE, 1.2, 90)
	get_tree().change_scene_to_file(LOBBY)


func _leave() -> void:
	game_match.leave()
	get_tree().change_scene_to_file(LOBBY if Session.mode == Session.Mode.ONLINE else MAIN_MENU)


# --- Views vs state -----------------------------------------------------------

## Debug guard: whenever nothing is moving, the views must mirror the state.
func _check_sync() -> void:
	for p in potions.size():
		var shown := potions[p].cards.map(func(v): return v.card.id)
		var real: Array = state.potions[p].map(func(c): return c.id)
		if shown != real:
			push_warning("Potion %d view out of sync, rebuilding from state" % p)
			_resync()
			return
	for d in decks.size():
		var top := state.top_card(d)
		var shown_top: CardView = decks[d].top_view
		if decks[d].count != state.middle_decks[d].size() or (top == null) != (shown_top == null) \
				or (top and shown_top and top.id != shown_top.card.id):
			_resync()
			return


## Rebuilds every potion, deck and plaque from the state, reusing card views by id.
func _resync() -> void:
	var views := {}
	for pv in potions:
		for v in pv.cards:
			views[v.card.id] = v
	for v in [_held, _swap.get("own_view"), _swap.get("other_view")]:
		if v:
			views[v.card.id] = v
	_held = null
	_swap = {}
	for p in potions.size():
		var pv := potions[p]
		pv.show_ghosts(false)
		pv.cards.clear()
		for c in state.potions[p]:
			var v: CardView = views.get(c.id)
			if v:
				views.erase(c.id)
			else:
				v = CardView.new(c)
				cards_layer.add_child(v)
				v.global_position = pv.global_position
			v.set_selected(false)
			v.z_index = 0
			pv.cards.append(v)
		pv.layout()
		pv.set_order(state.orders[p])
		pv.set_total(state.totals[p])
	for v in views.values():
		v.queue_free()
	for i in decks.size():
		decks[i].set_contents(state.middle_decks[i].size(), state.top_card(i), false)
	hud.show_skip(false)


# --- Input ------------------------------------------------------------------

func _add_target(node: Node2D, kind: String, data, glow := Color.WHITE) -> void:
	if director and not director.allows(kind, data):
		return
	targets.append({ "node": node, "kind": kind, "data": data })
	if node is CardView and kind != "held":
		node.set_glow(true, glow)


func _clear_targets() -> void:
	for t in targets:
		var n = t.node
		if not is_instance_valid(n):
			continue
		if n is CardView:
			n.set_glow(false)
			n.set_hover(false)
		elif n is GhostSlot:
			n.hovered = false
	targets.clear()
	_hovered = null


## Public so tests can drive it: acts as if `target` (an entry of `targets`) was clicked.
func click(target: Dictionary) -> void:
	if busy or not targets.has(target):
		return
	match target.kind:
		"deck": _pick_up(target.data)
		"held": _put_back()
		"slot":
			if mode == Mode.PLACE:
				_place(target.data)
			else:
				_place_swap(target.data)
		"own_card": _select_own(target.data)
		"other_card": _select_other(target.data[0], target.data[1])


func _unhandled_input(event: InputEvent) -> void:
	if busy:
		return
	if event is InputEventMouseMotion:
		_update_hover()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_hover()
		if _hovered != null:
			click(_hovered)


func _update_hover(at := Vector2.INF) -> void:
	var p := get_global_mouse_position() if at == Vector2.INF else at
	var found = null
	for i in range(targets.size() - 1, -1, -1):
		if _target_contains(targets[i], p):
			found = targets[i]
			break
	if found == _hovered:
		return
	if _hovered != null:
		_set_target_hover(_hovered, false)
	_hovered = found
	if found != null:
		_set_target_hover(found, true)


## Later targets win where they overlap. The held card slides over a hovered slot as a
## preview, so it is hit-tested where it rests; otherwise the preview would steal the
## hover from the slot, slide back, and loop.
func _target_contains(t: Dictionary, p: Vector2) -> bool:
	if not is_instance_valid(t.node):
		return false
	if t.kind == "held":
		return Rect2(_held_potion.held_position() - CardArt.SIZE / 2.0, CardArt.SIZE).has_point(p)
	return t.node.contains_global(p)


func _set_target_hover(t: Dictionary, on: bool) -> void:
	var n = t.node
	if not is_instance_valid(n):
		return
	if n is CardView:
		if not n.selected:
			n.set_hover(on)
	elif n is GhostSlot:
		n.hovered = on
		# Preview: the held card drifts over the hovered slot.
		if _held and _held_potion:
			var dest := _held_potion.held_position()
			if on:
				dest = n.global_position + _held_potion.toward_center() * CardArt.SIZE.y * 0.5
			_held.move_to(dest, 0.2)


func _process(delta: float) -> void:
	_time += delta
	if game_match:
		game_match.client_busy = busy or _pumping or not _events.is_empty()
	# Idle bob on the card waiting to be placed.
	if _held and not busy and not _held.hovered:
		_held.lift = 10.0 + 6.0 * sin(_time * 3.5)
