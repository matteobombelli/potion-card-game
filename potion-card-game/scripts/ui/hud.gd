class_name Hud
extends CanvasLayer
## In-game heads-up display: round counter, whose turn it is with a prompt, and
## the Skip swap button.

signal skip_pressed

var _round_label := Label.new()
var _turn_label := Label.new()
var _prompt_label := Label.new()
var _skip := UiKit.button("SKIP SWAP", 30, Palette.SWAP)


func _init() -> void:
	_round_label.label_settings = Fx.label_settings(30, Palette.TEXT_DIM, 8)
	_round_label.position = Vector2(28, 18)
	add_child(_round_label)

	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 36
	left.offset_top = -110
	left.custom_minimum_size = Vector2(420, 220)
	left.add_theme_constant_override("separation", 8)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	_turn_label.label_settings = Fx.label_settings(44, Palette.TITLE, 10)
	left.add_child(_turn_label)
	_prompt_label.label_settings = Fx.label_settings(26, Palette.TEXT, 7)
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.custom_minimum_size = Vector2(420, 0)
	left.add_child(_prompt_label)

	_skip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_skip.offset_left = -300
	_skip.offset_right = -40
	_skip.offset_top = -36
	_skip.offset_bottom = 36
	_skip.pressed.connect(skip_pressed.emit)
	_skip.hide()
	add_child(_skip)


func set_round(index: int, total: int) -> void:
	_round_label.text = "ROUND %d / %d" % [mini(index + 1, total), total]


## Sets the big title (e.g. "PLAYER 2") with a small pop, plus the instruction below it.
func set_turn(title: String, prompt: String) -> void:
	_prompt_label.text = prompt
	if _turn_label.text == title:
		return
	_turn_label.text = title
	_turn_label.pivot_offset = _turn_label.get_minimum_size() / 2.0
	_turn_label.scale = Vector2.ONE * 1.2
	_turn_label.create_tween().tween_property(_turn_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_prompt(prompt: String) -> void:
	_prompt_label.text = prompt


func clear() -> void:
	_turn_label.text = ""
	_prompt_label.text = ""


func show_skip(on: bool) -> void:
	if _skip.visible == on:
		return
	_skip.visible = on
	if on:
		_skip.pivot_offset = _skip.size / 2.0
		_skip.scale = Vector2.ZERO
		_skip.create_tween().tween_property(_skip, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
