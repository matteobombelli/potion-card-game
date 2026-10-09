class_name UiKit
extends RefCounted
## Shared control styling: buttons with a springy hover/press, and full-screen dims.


static func button(text: String, font_size := 34, accent := Palette.TARGET) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", Palette.TEXT_OUTLINE)
	b.add_theme_stylebox_override("normal", _box(Palette.PANEL, Palette.PANEL_BORDER))
	b.add_theme_stylebox_override("hover", _box(Palette.PANEL_HOVER, accent))
	b.add_theme_stylebox_override("pressed", _box(Palette.PANEL_PRESSED, accent))
	b.add_theme_stylebox_override("disabled", _box(Palette.PANEL_DISABLED, Palette.PANEL_BORDER.darkened(0.4)))
	b.mouse_entered.connect(func(): _spring(b, 1.08))
	b.mouse_exited.connect(func(): _spring(b, 1.0))
	b.button_down.connect(func(): _spring(b, 0.94))
	b.button_up.connect(func(): _spring(b, 1.08 if b.is_hovered() else 1.0))
	return b


## A full-screen rect that dims the table and swallows clicks behind an overlay.
static func dim(alpha := Palette.OVERLAY.a) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(Palette.OVERLAY, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


## Fades a control in; it ignores the mouse until fully visible, so nobody clicks
## a button they can't see yet.
static func fade_in(c: Control, duration := 0.3, delay := 0.0) -> Tween:
	var filter := c.mouse_filter
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_buttons_enabled(c, false)
	c.modulate.a = 0.0
	var t := c.create_tween()
	t.tween_interval(delay)
	t.tween_property(c, "modulate:a", 1.0, duration)
	t.tween_callback(func():
		c.mouse_filter = filter
		_set_buttons_enabled(c, true))
	return t


static func _set_buttons_enabled(root: Node, on: bool) -> void:
	if root is BaseButton:
		root.disabled = not on
	for child in root.get_children():
		_set_buttons_enabled(child, on)


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(4)
	s.set_corner_radius_all(14)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 5)
	return s


static func _spring(c: Control, s: float) -> void:
	c.pivot_offset = c.size / 2.0
	var t := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE * s, 0.15)
