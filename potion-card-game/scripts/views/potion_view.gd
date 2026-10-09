class_name PotionView
extends Node2D
## One player's seat: the potion row's card layout, drop slots, name plaque,
## score and special order tag. CardViews live in a shared layer; this node only
## tracks their order and target positions.

var player_index := 0
var top_seat := false   # seats at the top of the table: plaque above, held card below
var cards: Array[CardView] = []
var active := false

var ghost_left := GhostSlot.new()
var ghost_right := GhostSlot.new()
var _plaque := Node2D.new()
var _name_label := Label.new()
var _total_label := Label.new()
var _round_label := Label.new()
var _order_tag := PanelContainer.new()
var _order_label := Label.new()
var _order_style := StyleBoxFlat.new()
var _think_label := Label.new()
var _total_shown := 0
var _time := 0.0
var _thinking := false


func setup(p_index: int, p_top_seat: bool, p_name := "") -> void:
	player_index = p_index
	top_seat = p_top_seat
	ghost_left.side = GameState.Side.LEFT
	ghost_right.side = GameState.Side.RIGHT
	for g in [ghost_left, ghost_right]:
		g.hide()
		add_child(g)

	var plaque_y := CardArt.SIZE.y / 2.0 + 42.0
	_plaque.position = Vector2(0, -plaque_y if top_seat else plaque_y)
	add_child(_plaque)
	_name_label.text = p_name if p_name != "" else "PLAYER %d" % (p_index + 1)
	_name_label.label_settings = Fx.label_settings(30, Palette.TEXT, 8)
	_plaque.add_child(_name_label)
	_think_label.text = "..."
	_think_label.label_settings = Fx.label_settings(30, Palette.TITLE, 8)
	_think_label.hide()
	_plaque.add_child(_think_label)
	_total_label.label_settings = Fx.label_settings(38, Palette.SCORE, 8)
	_plaque.add_child(_total_label)
	_round_label.label_settings = Fx.label_settings(30, Palette.POSITIVE, 8)
	_round_label.modulate.a = 0.0
	_plaque.add_child(_round_label)

	_order_style.bg_color = Palette.TAG_BG
	_order_style.set_border_width_all(3)
	_order_style.set_corner_radius_all(10)
	_order_style.content_margin_left = 12
	_order_style.content_margin_right = 12
	_order_style.content_margin_top = 2
	_order_style.content_margin_bottom = 2
	_order_tag.add_theme_stylebox_override("panel", _order_style)
	_order_label.label_settings = Fx.label_settings(22, Palette.TEXT, 6)
	_order_tag.add_child(_order_label)
	_order_tag.hide()
	_plaque.add_child(_order_tag)
	_set_total_text(0)


func _process(delta: float) -> void:
	if active or _thinking:
		_time += delta
	if active:
		queue_redraw()
	if _thinking:
		_think_label.text = ".".repeat(1 + int(_time * 3.0) % 3)


func set_player_name(n: String) -> void:
	_name_label.text = n
	_layout_plaque()


## Pulsing dots by the name while this player (CPU or remote) decides.
func set_thinking(on: bool) -> void:
	_thinking = on
	_think_label.visible = on


func _draw() -> void:
	var w := spacing() * Rules.POTION_SIZE + 40
	var h := CardArt.SIZE.y + 36
	var r := Rect2(Vector2(-w / 2, -h / 2), Vector2(w, h))
	draw_rect(r, Palette.SEAT_FILL)
	if active:
		var a := 0.35 + 0.2 * sin(_time * 4.0)
		draw_rect(r, Color(Palette.SEAT_ACTIVE, a), false, 5.0)
		draw_rect(r.grow(8), Color(Palette.SEAT_ACTIVE, a * 0.35), false, 3.0)
	else:
		draw_rect(r, Palette.SEAT_BORDER, false, 2.0)


func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	queue_redraw()
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_plaque, "scale", Vector2.ONE * (1.15 if on else 1.0), 0.25)
	_name_label.label_settings.font_color = Palette.TITLE if on else Palette.TEXT


# --- Layout -----------------------------------------------------------------

func spacing() -> float:
	return CardArt.SIZE.x + 14.0


func slot_position(i: int, count: int) -> Vector2:
	return global_position + Vector2((i - (count - 1) / 2.0) * spacing(), 0)


## Where a card hovers before being placed here (toward the table centre).
func held_position() -> Vector2:
	return global_position + toward_center() * CardArt.SIZE.y * 0.95


func toward_center() -> Vector2:
	return Vector2.DOWN if top_seat else Vector2.UP


func layout(duration := 0.3) -> void:
	for i in cards.size():
		cards[i].move_to(slot_position(i, cards.size()), duration)


## Adds a card view at one end (mirroring GameState) and returns its slot position.
func insert(v: CardView, side: int) -> Vector2:
	if side == GameState.Side.LEFT:
		cards.push_front(v)
	else:
		cards.push_back(v)
	return slot_position(cards.find(v), cards.size())


func show_ghosts(on: bool) -> void:
	for g in [ghost_left, ghost_right]:
		g.hovered = false
		g.hide()
	if not on:
		return
	var n := cards.size()
	if n == 0:
		ghost_left.global_position = slot_position(0, 1)   # an empty potion has a single slot
		ghost_left.appear()
		return
	ghost_left.global_position = slot_position(-1, n)
	ghost_right.global_position = slot_position(n, n)
	ghost_left.appear()
	ghost_right.appear()


func ghosts() -> Array:
	return [ghost_left, ghost_right].filter(func(g): return g.visible)


# --- Score and order --------------------------------------------------------

## Animated count-up of the running total on the plaque.
func set_total(v: int) -> void:
	var from := _total_shown
	_total_shown = v
	var t := create_tween()
	t.tween_method(func(x: float): _set_total_text(roundi(x)), float(from), float(v), 0.5)
	t.tween_property(_total_label, "scale", Vector2.ONE * 1.35, 0.06)
	t.tween_property(_total_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func set_round_score(v: int) -> void:
	_round_label.text = "%+d" % v if v != 0 else "0"
	_round_label.modulate.a = 1.0
	_round_label.label_settings.font_color = Palette.POSITIVE if v >= 0 else Palette.NEGATIVE
	_layout_plaque()
	_round_label.pivot_offset = _round_label.get_minimum_size() / 2.0
	var t := create_tween()
	t.tween_property(_round_label, "scale", Vector2.ONE * 1.3, 0.05)
	t.tween_property(_round_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_round_score() -> void:
	create_tween().tween_property(_round_label, "modulate:a", 0.0, 0.3)


## Shows the special order this player kept (null hides it; a hidden order shows as secret).
func set_order(order: SpecialOrder) -> void:
	if order == null:
		_order_tag.hide()
		_layout_plaque()
		return
	if order.is_hidden():
		set_order_hidden()
		return
	_order_label.text = "%s  +%d" % [order.title(), order.points]
	_order_style.border_color = CardArt.fx_color(order.color).lightened(0.25) if order.color >= 0 else Palette.ORDER_NEUTRAL
	_show_order_tag()


## Another player has chosen an order you can't see yet.
func set_order_hidden() -> void:
	_order_label.text = "SECRET ORDER"
	_order_style.border_color = Palette.PANEL_BORDER
	_show_order_tag()


func has_hidden_order() -> bool:
	return _order_tag.visible and _order_label.text == "SECRET ORDER"


## Flips a secret order over to show what it was.
func reveal_order(order: SpecialOrder) -> void:
	var t := _order_tag.create_tween()
	_order_tag.pivot_offset = _order_tag.get_combined_minimum_size() / 2.0
	t.tween_property(_order_tag, "scale:x", 0.0, 0.12)
	t.tween_callback(func(): set_order(order))


func _show_order_tag() -> void:
	_order_tag.modulate = Color.WHITE
	_order_tag.show()
	_layout_plaque()
	_order_tag.pivot_offset = _order_tag.get_combined_minimum_size() / 2.0
	_order_tag.scale = Vector2.ZERO
	_order_tag.create_tween().tween_property(_order_tag, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Scoring feedback: a met order pops, a missed one fades.
func show_order_result(met: bool) -> void:
	if met:
		var t := _order_tag.create_tween()
		t.tween_property(_order_tag, "scale", Vector2.ONE * 1.25, 0.08)
		t.tween_property(_order_tag, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_order_tag.create_tween().tween_property(_order_tag, "modulate", Color(1, 1, 1, 0.35), 0.3)


func order_tag_global_position() -> Vector2:
	return _plaque.to_global(_order_tag.position + _order_tag.get_combined_minimum_size() / 2.0)


func _set_total_text(v: int) -> void:
	_total_label.text = "%d pts" % v
	_layout_plaque()


## Lays the plaque out in a row: name, total, order tag, then the round score.
func _layout_plaque() -> void:
	var gap := 24.0
	var nw := _name_label.get_minimum_size()
	var tw := _total_label.get_minimum_size()
	var ow := _order_tag.get_combined_minimum_size() if _order_tag.visible else Vector2.ZERO
	var rw := _round_label.get_minimum_size()
	var total_w := nw.x + gap + tw.x + (gap + ow.x if _order_tag.visible else 0.0)
	var x := -total_w / 2.0
	_name_label.position = Vector2(x, -nw.y / 2.0)
	x += nw.x + gap
	_total_label.position = Vector2(x, -tw.y / 2.0)
	_total_label.pivot_offset = tw / 2.0
	x += tw.x + gap
	_order_tag.position = Vector2(x, -ow.y / 2.0)
	_think_label.position = Vector2(-total_w / 2.0 - 52.0, -nw.y / 2.0)
	_round_label.position = Vector2(total_w / 2.0 + gap, -rw.y / 2.0)
