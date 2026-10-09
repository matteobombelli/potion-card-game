class_name OrderChoiceOverlay
extends CanvasLayer
## Full-screen choice between your offered special orders. The tutorial can
## allow only one of them.

signal chosen(index: int)

var _closing := false
var _buttons: Array[Button] = []


func _init(title_text: String, offers: Array, allowed := -1) -> void:
	layer = 3
	add_child(UiKit.dim())
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 30)
	add_child(box)

	var title := Label.new()
	title.text = title_text
	title.label_settings = Fx.label_settings(48, Palette.TITLE, 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	box.add_child(row)
	for i in offers.size():
		var o: SpecialOrder = offers[i]
		var accent := CardArt.fx_color(o.color).lightened(0.25) if o.color >= 0 else Palette.ORDER_NEUTRAL
		var b := UiKit.button("+%d\n%s" % [o.points, o.description()], 28, accent)
		b.custom_minimum_size = Vector2(420, 200)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_on_pressed.bind(i))
		row.add_child(b)
		_buttons.append(b)
	UiKit.fade_in(row, 0.2)
	if allowed >= 0:
		# Once the fade-in has re-enabled the buttons, lock all but the allowed one.
		var t := row.create_tween()
		t.tween_interval(0.25)
		t.tween_callback(func():
			for i in _buttons.size():
				if i != allowed:
					_buttons[i].disabled = true
					_buttons[i].modulate.a = 0.45)


## Screen-space centre of offer button `i` (for tutorial tips).
func button_center(i: int) -> Vector2:
	return _buttons[i].get_global_rect().get_center() if i < _buttons.size() else Vector2.ZERO


func _on_pressed(i: int) -> void:
	if _closing:
		return
	_closing = true
	chosen.emit(i)


## Accepts clicks again after a click the game couldn't take.
func unlock() -> void:
	_closing = false


## Fades out and frees itself.
func close() -> void:
	for c in get_children():
		c.create_tween().tween_property(c, "modulate:a", 0.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(queue_free)
