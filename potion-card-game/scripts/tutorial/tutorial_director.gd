class_name TutorialDirector
extends Node
## Walks the game controller through TutorialScript.BEATS: shows tips, lets only
## the scripted target be clicked, pauses the CPU while a tip waits for NEXT and
## annotates the scoring. Once the beats run out (rounds 3–4) it steps aside.
##
## The game calls the hooks below at fixed points, in a fixed order, so a single
## cursor into BEATS is enough to know where the lesson is.

const STEP_KIND := { "pick": "deck", "place": "slot", "swap_own": "own_card", "swap_other": "other_card",
	"swap_place_other": "slot", "swap_place_own": "slot" }

var game: Node
var local_match: LocalMatch
var tip := TutorialTip.new()
var _beat := 0
var _shown := -1             # beat whose tip is on screen
var _mod_hit_noted := false


func _init(p_game: Node, p_match: LocalMatch) -> void:
	game = p_game
	local_match = p_match


func _ready() -> void:
	add_child(tip)


## True while the scripted part of the lesson is running.
func active() -> bool:
	return _beat < TutorialScript.BEATS.size()


func _current() -> Dictionary:
	return TutorialScript.BEATS[_beat] if active() else {}


# --- Hooks called by the game ---------------------------------------------------

## Whether a target may be clicked. Putting a card back is off during the lesson.
func allows(kind: String, data) -> bool:
	var b := _current()
	if b.is_empty():
		return true
	if not b.has("step") or STEP_KIND.get(b.step, "") != kind:
		return false
	return data == b.allow


func allows_skip() -> bool:
	return not active()


func allowed_order() -> int:
	var b := _current()
	return b.allow if b.get("step") == "order" else -1


## Your step has started: show its tips (any "pre" tips first, with NEXT).
## Pre tips appear just after the step starts; they block clicks until NEXT.
func before_step(step: String) -> void:
	var b := _current()
	if b.get("step") != step or _shown == _beat:
		return
	_shown = _beat
	var beat := _beat
	await get_tree().create_timer(0.1).timeout   # let overlays lay out before pointing at them
	for text in b.get("pre", []):
		if _beat != beat:
			return
		await _show_and_wait(text, Vector2.INF)
	if _beat == beat:
		tip.show_tip(b.tip, _point(b.get("point", "")))


## You completed the current step.
func step_done() -> void:
	if active() and _current().has("step"):
		tip.hide_tip()
		_beat += 1


## After the CPU's move has been shown.
func after_event(action: Dictionary) -> void:
	var b := _current()
	if b.get("after") != action.get("type") or int(action.get("player", -1)) == game.me:
		return
	_beat += 1
	for text in b.tips:
		await _show_and_wait(text, Vector2.INF)


## A Callable for ScoreSequence that pauses on the stages the lesson explains.
func score_hook(player: int) -> Callable:
	var rnd: int = game.state.round_index
	if rnd >= TutorialScript.SCORE_NOTES.size() or not TutorialScript.SCORE_NOTES[rnd].has(player):
		return Callable()
	_mod_hit_noted = false
	var notes: Dictionary = TutorialScript.SCORE_NOTES[rnd][player]
	var b: Dictionary = game.state.last_round_scores[player]
	var pv: PotionView = game.potions[player]
	return func(stage: String, info: Dictionary) -> void:
		if not notes.has(stage) or (stage == "mod_hit" and _mod_hit_noted):
			return
		if stage == "mod_hit":
			_mod_hit_noted = true
		var text: String = notes[stage].format({
			"running": info.get("running", 0), "total": b.total,
			"pts": b.bonus.pts if stage == "bonus" else b.order.get("pts", 0),
			"name": b.bonus.name.to_upper(),
		})
		await _show_and_wait(text, _to_screen(pv.global_position))


func before_next_round(round_index: int) -> void:
	var b := _current()
	if b.get("round_end", -1) != round_index:
		return
	_beat += 1
	for text in b.tips:
		await _show_and_wait(text, Vector2.INF)


# --- Autoplay -------------------------------------------------------------------

func waiting_for_next() -> bool:
	return tip.is_waiting()


func next() -> void:
	if tip.is_waiting():
		tip.next_pressed.emit()


# --- Internals -------------------------------------------------------------------

func _show_and_wait(text: String, target: Vector2) -> void:
	local_match.hold_bots = true
	tip.show_tip(text, target, true)
	await tip.next_pressed
	tip.hide_tip()
	local_match.hold_bots = false


## Screen position for a "point" spec.
func _point(spec: String) -> Vector2:
	var parts := spec.split(":")
	match parts[0]:
		"order":
			if game._order_overlay:
				return game._order_overlay.button_center(int(parts[1]))
		"deck":
			return _to_screen(game.decks[int(parts[1])].global_position)
		"slot":
			var pv: PotionView = game._held_potion
			if pv:
				var g: GhostSlot = pv.ghost_left if int(parts[1]) == GameState.Side.LEFT or pv.cards.is_empty() else pv.ghost_right
				return _to_screen(g.global_position)
		"card":
			var cards: Array = game.potions[int(parts[1])].cards
			var i := int(parts[2])
			if i < cards.size():
				return _to_screen(cards[i].global_position)
	return Vector2.INF


func _to_screen(world: Vector2) -> Vector2:
	return game.get_viewport().get_canvas_transform() * world
