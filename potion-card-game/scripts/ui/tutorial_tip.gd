class_name TutorialTip
extends CanvasLayer
## A tutorial speech panel with an optional NEXT button and an arrow pointing at
## a spot on screen. While NEXT is showing, the rest of the screen is dimmed
## slightly and can't be clicked.

signal next_pressed

const WIDTH := 560.0
const GAP := 150.0   # distance between the pointed-at spot and the panel

var _blocker := ColorRect.new()
var _panel := UiKit.panel(24)
var _text := Label.new()
var _next := UiKit.button("NEXT", 28)
var _arrow := _Arrow.new()


func _init() -> void:
	layer = 4
	_blocker.color = Color(Palette.OVERLAY, 0.25)
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_blocker)
	add_child(_arrow)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	_text.label_settings = Fx.label_settings(27, Palette.TEXT, 6)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_child(_text)
	_next.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next.pressed.connect(next_pressed.emit)
	box.add_child(_next)
	add_child(_panel)
	hide_tip()


## Shows `text`. `target` is a screen position to point at (Vector2.INF for none).
func show_tip(text: String, target := Vector2.INF, with_next := false) -> void:
	visible = true
	_text.text = text
	_next.visible = with_next
	_blocker.visible = with_next
	_panel.reset_size()
	var screen := get_viewport().get_visible_rect().size
	var sz := _panel.get_combined_minimum_size()
	var pos: Vector2
	if target == Vector2.INF:
		pos = Vector2((screen.x - sz.x) / 2.0, 130)
	else:
		var y := target.y - GAP - sz.y if target.y > screen.y * 0.5 else target.y + GAP
		pos = Vector2(clampf(target.x - sz.x / 2.0, 20, screen.x - sz.x - 20), clampf(y, 20, screen.y - sz.y - 20))
	_panel.position = pos
	_arrow.set_points(Rect2(pos, sz), target)
	_panel.modulate.a = 0.0
	_panel.create_tween().tween_property(_panel, "modulate:a", 1.0, 0.2)
	if with_next:
		UiKit.fade_in(_next, 0.2, 0.35)   # a short pause so a stray click can't skip the tip


func hide_tip() -> void:
	visible = false


## A NEXT tip is up (the game can't be clicked), even while its button fades in.
func blocking() -> bool:
	return visible and _next.visible


func is_waiting() -> bool:
	return visible and _next.visible and not _next.disabled


class _Arrow extends Control:
	var _from := Vector2.ZERO
	var _to := Vector2.INF
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func set_points(panel: Rect2, target: Vector2) -> void:
		_to = target
		if target != Vector2.INF:
			var c := panel.get_center()
			_from = Vector2(clampf(target.x, panel.position.x + 30, panel.end.x - 30),
				panel.end.y if target.y > c.y else panel.position.y)
		queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		if _to != Vector2.INF:
			queue_redraw()

	func _draw() -> void:
		if _to == Vector2.INF:
			return
		var dir := (_to - _from).normalized()
		var tip := _to - dir * (70.0 + 10.0 * sin(_time * 5.0))
		draw_line(_from, tip, Palette.TITLE, 6.0, true)
		var side := Vector2(-dir.y, dir.x) * 18.0
		draw_colored_polygon(PackedVector2Array([tip + dir * 26.0, tip + side, tip - side]), Palette.TITLE)
