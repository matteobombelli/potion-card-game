extends TableRoot
## Game controller for local play: owns the GameState, turns clicks into rules
## actions and plays the animations.
##
## Flow: _advance() looks at the rules phase and sets up the next step. Each step
## builds a list of clickable `targets`; a click calls the handler for its kind.
## Nothing reaches GameState until a move is complete (a card placed, a swap
## finished), so a held card can still be put back. Views then mirror the state;
## _resync() rebuilds them from GameState if they ever disagree, which is also
## how a networked client would apply state it receives.

enum Mode { NONE, CHOOSE_ORDER, PICK, PLACE, SWAP_OWN, SWAP_OTHER, SWAP_PLACE_OTHER, SWAP_PLACE_OWN }

const MAIN_MENU := "res://scenes/main_menu.tscn"

var state: GameState
var decks: Array[MiddleDeckView] = []
var potions: Array[PotionView] = []
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
var _time := 0.0


func _ready() -> void:
	state = GameState.new(Session.num_players)
	hud.skip_pressed.connect(skip_swap)
	add_child(hud)
	_build_board()
	hud.set_round(state.round_index, Rules.ROUNDS)
	await _deal()
	await Fx.banner("ROUND 1", Palette.TITLE, 0.5)
	_advance()


func _build_board() -> void:
	var seats := TableLayout.seats(state.num_players)
	for i in state.num_players:
		var pv := PotionView.new()
		pv.position = seats[i].position
		board_layer.add_child(pv)
		pv.setup(i, seats[i].top)
		potions.append(pv)
	for pos in TableLayout.deck_positions(state.middle_decks.size()):
		var d := MiddleDeckView.new()
		d.position = pos
		board_layer.add_child(d)
		decks.append(d)


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

## Sets up whatever the rules engine is waiting for next.
func _advance() -> void:
	busy = false
	_clear_targets()
	_check_sync()
	match state.phase:
		GameState.Phase.CHOOSE_ORDER: _begin_order_choice()
		GameState.Phase.PLAY: _begin_pick()
		GameState.Phase.SWAP: _begin_swap()
		GameState.Phase.ROUND_OVER: _play_round_end()
		GameState.Phase.GAME_OVER: _show_game_over()


func _set_active(player: int) -> void:
	for i in potions.size():
		potions[i].set_active(i == player)


func _player_title() -> String:
	return "PLAYER %d" % (state.current_player + 1)


# --- Special order choice ---------------------------------------------------

func _begin_order_choice() -> void:
	mode = Mode.CHOOSE_ORDER
	var p := state.current_player
	_set_active(p)
	hud.set_turn(_player_title(), "Choose your special order for this round.")
	_order_overlay = OrderChoiceOverlay.new(p, state.order_offers[p])
	_order_overlay.chosen.connect(choose_order)
	add_child(_order_overlay)


## Public so tests can drive it; the overlay calls it on click.
func choose_order(offer_idx: int) -> void:
	if busy or mode != Mode.CHOOSE_ORDER:
		return
	var p := state.current_player
	if not state.choose_order(p, offer_idx):
		return
	busy = true
	potions[p].set_order(state.orders[p])
	_order_overlay.close()
	_order_overlay = null
	await get_tree().create_timer(0.25).timeout
	_advance()


# --- Taking and placing a card ----------------------------------------------

func _begin_pick() -> void:
	mode = Mode.PICK
	var p := state.current_player
	_set_active(p)
	hud.set_turn(_player_title(), "Take the top card of any middle deck.")
	for i in decks.size():
		if state.can_play(p, i) and decks[i].top_view:
			_add_target(decks[i].top_view, "deck", i, Palette.TARGET)


func _pick_up(deck_idx: int) -> void:
	busy = true
	_clear_targets()
	_held = decks[deck_idx].lift_top(cards_layer)
	_held.z_index = 10
	_held_from = deck_idx
	var potion := potions[state.current_player]
	await _held.fly_to(potion.held_position(), 0.38, -160.0).finished
	mode = Mode.PLACE
	_add_target(_held, "held", null)   # added before the slots so the slots win where they overlap
	_offer_slots(potion, "Place it on the left or right end of your potion. Click the card to put it back.")
	busy = false


func _put_back() -> void:
	busy = true
	_clear_targets()
	_held_potion.show_ghosts(false)
	var v := _held
	_held = null
	await v.fly_to(decks[_held_from].global_position, 0.3, -100.0).finished
	v.z_index = 0
	decks[_held_from].put_back(v)
	_advance()


func _place(side: int) -> void:
	busy = true
	_clear_targets()
	_held_potion.show_ghosts(false)
	var p := state.current_player
	if not state.play_card(p, _held_from, side):
		push_error("GameState rejected play_card(%d, %d, %d)" % [p, _held_from, side])
		_resync()
		_advance()
		return
	var v := _held
	_held = null
	decks[_held_from].set_contents(state.middle_decks[_held_from].size(), state.top_card(_held_from))
	await v.slam_to(potions[p].insert(v, side))
	potions[p].layout(0.35)
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
	hud.show_skip(true)
	hud.set_prompt("Black card! You may swap one of your colour cards with another player's. Pick your card, or skip.")
	var p := state.current_player
	for i in potions[p].cards.size():
		if state.is_swappable(p, i):
			_add_target(potions[p].cards[i], "own_card", i, Palette.SWAP)


func _select_own(idx: int) -> void:
	var p := state.current_player
	var v := potions[p].cards[idx]
	var previous: CardView = _swap.get("own_view")
	_clear_targets()
	if previous:
		previous.set_selected(false)
	if previous == v:   # clicking the selected card again deselects it
		_begin_swap()
		return
	_swap = { "own_idx": idx, "own_view": v }
	v.set_selected(true)
	mode = Mode.SWAP_OTHER
	hud.set_prompt("Now pick another player's colour card to take. (Click your card again to change.)")
	for i in potions[p].cards.size():
		if state.is_swappable(p, i):
			_add_target(potions[p].cards[i], "own_card", i, Color.WHITE if i == idx else Palette.SWAP)
	for other in potions.size():
		if other == p:
			continue
		for i in potions[other].cards.size():
			if state.is_swappable(other, i):
				_add_target(potions[other].cards[i], "other_card", [other, i], Palette.TARGET)


## Both cards leave their potions and cross over, then each gets placed.
func _select_other(other: int, idx: int) -> void:
	busy = true
	_clear_targets()
	hud.show_skip(false)
	var mine := potions[state.current_player]
	var theirs := potions[other]
	var a: CardView = _swap.own_view
	var b := theirs.cards[idx]
	_swap.merge({ "other_player": other, "other_idx": idx, "other_view": b })
	a.set_selected(false)
	mine.cards.erase(a)
	theirs.cards.erase(b)
	mine.layout(0.35)
	theirs.layout(0.35)
	a.z_index = 10
	b.z_index = 10
	var trails := [Fx.trail(a, CardArt.fx_color(a.card.color)), Fx.trail(b, CardArt.fx_color(b.card.color))]
	await get_tree().create_timer(0.12).timeout
	a.fly_to(theirs.held_position(), 0.55, -260.0, TAU)
	await b.fly_to(mine.held_position(), 0.55, 260.0, -TAU).finished
	for t in trails:
		Fx.stop_trail(t)
	_held = a
	mode = Mode.SWAP_PLACE_OTHER
	_offer_slots(theirs, "Choose where your card goes in Player %d's potion." % (other + 1))
	busy = false


func _place_swap(side: int) -> void:
	busy = true
	_clear_targets()
	_held_potion.show_ghosts(false)
	var v := _held
	_held = null
	if mode == Mode.SWAP_PLACE_OTHER:
		_swap.other_side = side
		await v.slam_to(_held_potion.insert(v, side))
		_held_potion.layout(0.35)
		_held = _swap.other_view
		mode = Mode.SWAP_PLACE_OWN
		_offer_slots(potions[state.current_player], "Choose where your new card goes in your potion.")
		busy = false
		return

	# Both ends chosen: commit the swap, then land the last card.
	var p := state.current_player
	if not state.swap(p, _swap.own_idx, _swap.other_player, _swap.other_idx, _swap.other_side, side):
		push_error("GameState rejected swap %s" % _swap)
		_resync()
		_advance()
		return
	_swap = {}
	await v.slam_to(potions[p].insert(v, side))
	potions[p].layout(0.35)
	_advance()


## Public so tests can drive it; the HUD button calls it.
func skip_swap() -> void:
	if busy or not (mode == Mode.SWAP_OWN or mode == Mode.SWAP_OTHER):
		return
	if not state.skip_swap(state.current_player):
		return
	if _swap.has("own_view"):
		_swap.own_view.set_selected(false)
	_swap = {}
	hud.show_skip(false)
	_advance()


# --- Round end and game over ------------------------------------------------

func _play_round_end() -> void:
	busy = true
	mode = Mode.NONE
	_set_active(-1)
	hud.set_turn("SCORING", "Every potion is complete. Let's see what you brewed!")
	await get_tree().create_timer(0.4).timeout
	for p in potions.size():
		potions[p].set_active(true)
		await ScoreSequence.run(potions[p], state.last_round_scores[p])
		potions[p].set_total(state.totals[p])
		await get_tree().create_timer(0.5).timeout
		potions[p].set_active(false)
	await get_tree().create_timer(0.6).timeout
	await _sweep_cards()
	for pv in potions:
		pv.hide_round_score()
		pv.set_order(null)
	state.next_round()
	if state.phase != GameState.Phase.GAME_OVER:
		hud.set_round(state.round_index, Rules.ROUNDS)
		var last := state.round_index == Rules.ROUNDS - 1
		await Fx.banner("FINAL ROUND" if last else "ROUND %d" % (state.round_index + 1), Palette.TITLE, 0.5)
	_advance()


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
	busy = true
	mode = Mode.NONE
	_set_active(-1)
	hud.clear()
	for d in decks:   # leftover middle decks tumble off the table
		var t := d.create_tween().set_parallel()
		t.tween_property(d, "position", d.position + Vector2(randf_range(-150, 150), 800), 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(d, "rotation", randf_range(-1.5, 1.5), 0.6)
	var overlay := GameOverOverlay.new(state.totals, state.winners())
	overlay.play_again.connect(func(): get_tree().reload_current_scene())
	overlay.main_menu.connect(func(): get_tree().change_scene_to_file(MAIN_MENU))
	add_child(overlay)


# --- Views vs state -----------------------------------------------------------

## Debug guard: after every completed action the views must mirror GameState.
func _check_sync() -> void:
	for p in potions.size():
		var shown := potions[p].cards.map(func(v): return v.card)
		if shown != state.potions[p]:
			push_warning("Potion %d view out of sync, rebuilding from state" % p)
			_resync()
			return


## Rebuilds every potion and deck view from GameState, reusing card views by id.
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
	for v in views.values():
		v.queue_free()
	for i in decks.size():
		decks[i].set_contents(state.middle_decks[i].size(), state.top_card(i), false)
	hud.show_skip(false)


# --- Input ------------------------------------------------------------------

func _add_target(node: Node2D, kind: String, data, glow := Color.WHITE) -> void:
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
	# Idle bob on the card waiting to be placed.
	if _held and not busy and not _held.hovered:
		_held.lift = 10.0 + 6.0 * sin(_time * 3.5)
