class_name OrderChoiceOverlay
extends CanvasLayer
## Full-screen choice between a player's offered special orders.

signal chosen(index: int)

var _closing := false


func _init(player: int, offers: Array) -> void:
	layer = 3
	add_child(UiKit.dim())
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 30)
	add_child(box)

	var title := Label.new()
	title.text = "PLAYER %d: CHOOSE A SPECIAL ORDER" % (player + 1)
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
	UiKit.fade_in(row, 0.2)


func _on_pressed(i: int) -> void:
	if _closing:
		return
	_closing = true
	chosen.emit(i)


## Fades out and frees itself.
func close() -> void:
	for c in get_children():
		c.create_tween().tween_property(c, "modulate:a", 0.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(queue_free)
