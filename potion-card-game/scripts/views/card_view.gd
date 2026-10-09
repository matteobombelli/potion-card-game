class_name CardView
extends Node2D
## Visual for one card: drop shadow, selection glow and the sprite stack from CardArt.
## The root node is moved by layouts and animations; `body` carries lift/squash/tilt.
##
## All movement goes through move_tween(), which cancels any movement already in
## progress, so animations never fight over the card's position.

const HOVER_LIFT := 14.0
const SELECT_LIFT := 26.0

var card: CardData
var body := Node2D.new()
var shadow := Sprite2D.new()
var glow := Sprite2D.new()
var _face: Array[Sprite2D] = []
var _materials: Array[ShaderMaterial] = []

var hovered := false
var selected := false
var glow_on := false
var glow_color := Color.WHITE
var lift := 0.0:
	set(v):
		lift = v
		body.position.y = -v
		shadow.position = Vector2(6, 9) + Vector2(lift * 0.35, lift * 0.6)
		shadow.modulate.a = clampf(0.35 - lift * 0.004, 0.15, 0.35)
var flash_amount := 0.0:
	set(v):
		flash_amount = v
		for m in _materials:
			m.set_shader_parameter("flash", v)

var _time := randf() * 10.0
var _lift_tween: Tween
var _move: Tween
var _tilt_target := 0.0


func _init(p_card: CardData = null) -> void:
	shadow.texture = CardArt.BACKING
	shadow.scale = Vector2.ONE * CardArt.SCALE
	shadow.material = CardArt.make_material(CardArt.SHADOW_TINT, CardArt.BACKING_REF, true)
	add_child(shadow)
	glow.texture = CardArt.BACKING
	glow.scale = Vector2(CardArt.SCALE * 1.12, CardArt.SCALE * 1.09)
	glow.material = CardArt.make_material(Color.WHITE, CardArt.BACKING_REF, true)
	glow.modulate.a = 0.0
	body.add_child(glow)
	add_child(body)
	lift = 0.0
	if p_card:
		set_card(p_card)


## Builds the card face. This is the one place that decides what a card looks like.
func set_card(p_card: CardData) -> void:
	card = p_card
	for s in _face:
		s.queue_free()
	_face.clear()
	_materials.clear()

	_add_sprite(CardArt.BACKING, CardArt.make_material(CardArt.card_tint(card.color)))
	var ink := CardArt.INK_LIGHT if card.is_black() else CardArt.INK_DARK
	if card.value < 0:
		_add_sprite(CardArt.MINUS, CardArt.make_material(ink, 1.0, true))
	_add_sprite(CardArt.digit(card.value), CardArt.make_material(ink, 1.0, true))
	if card.has_modifier():
		var icon := CardArt.icon_tint(card.modifier_color)
		var m := CardArt.make_material(icon, CardArt.MODIFIER_REF, true)
		# Dark outline so an icon matching the card's own colour still reads.
		if card.modifier_color != CardData.CardColor.BLACK:
			m.set_shader_parameter("outline", 1.0)
			m.set_shader_parameter("outline_color", icon.darkened(0.7))
		_add_sprite(CardArt.MODIFIERS[card.modifier], m)
	flash_amount = flash_amount


func _add_sprite(tex: Texture2D, mat: ShaderMaterial) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE * CardArt.SCALE
	s.material = mat
	body.add_child(s)
	_face.append(s)
	_materials.append(mat)


func _process(delta: float) -> void:
	_time += delta
	if glow_on:
		glow.modulate = Color(glow_color, 0.45 + 0.35 * sin(_time * 5.0))
	elif glow.modulate.a > 0.0:
		glow.modulate.a = move_toward(glow.modulate.a, 0.0, delta * 4.0)
	_tilt_target = clampf((get_global_mouse_position().x - global_position.x) * 0.0016, -0.09, 0.09) if hovered else 0.0
	body.rotation = lerpf(body.rotation, _tilt_target, minf(1.0, delta * 12.0))


# --- State ------------------------------------------------------------------

func set_glow(on: bool, color := Color.WHITE) -> void:
	glow_on = on
	glow_color = color


func set_hover(on: bool) -> void:
	if hovered == on:
		return
	hovered = on
	_tween_lift()


func set_selected(on: bool) -> void:
	if selected == on:
		return
	selected = on
	_tween_lift()


func _tween_lift() -> void:
	z_index = 5 if hovered or selected else 0
	var target := SELECT_LIFT if selected else (HOVER_LIFT if hovered else 0.0)
	var s := 1.06 if hovered or selected else 1.0
	if _lift_tween:
		_lift_tween.kill()
	_lift_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_lift_tween.tween_property(self, "lift", target, 0.18)
	_lift_tween.tween_property(body, "scale", Vector2.ONE * s, 0.18)


func contains_global(p: Vector2) -> bool:
	var l := to_local(p) - body.position
	return Rect2(-CardArt.SIZE / 2.0, CardArt.SIZE).grow(4).has_point(l)


func icon_global_position() -> Vector2:
	return to_global(body.position + CardArt.modifier_icon_offset(card.modifier))


# --- Movement ---------------------------------------------------------------

## A fresh tween for moving this card; any movement already in progress is cancelled.
func move_tween() -> Tween:
	if _move:
		_move.kill()
	_move = create_tween()
	return _move


## Glides to a position (and upright), with a little overshoot.
func move_to(to: Vector2, duration := 0.3) -> Tween:
	var t := move_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", to, duration)
	t.tween_property(self, "rotation", 0.0, duration)
	return t


## Flies along a curved arc. `arc` bends the path vertically; `spin` adds rotation (radians).
func fly_to(to: Vector2, duration: float, arc := -120.0, spin := 0.0) -> Tween:
	var from := global_position
	var ctrl := (from + to) / 2.0 + Vector2(-arc * 0.3, arc)
	var start_rot := rotation
	var t := move_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(x: float):
		global_position = from.lerp(ctrl, x).lerp(ctrl.lerp(to, x), x)
		rotation = start_rot + spin * x, 0.0, 1.0, duration)
	# Normalise so a later move_to() doesn't unwind a full spin.
	t.tween_callback(func(): rotation = wrapf(start_rot + spin, -PI, PI))
	return t


## Lifts, then slams down onto `to` with the landing effects. Await it.
func slam_to(to: Vector2) -> void:
	z_index = 10
	lift = 0.0
	var t := move_tween()
	t.tween_property(self, "global_position", to + Vector2(0, -70), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "scale", Vector2.ONE * 1.25, 0.13)
	t.parallel().tween_property(self, "rotation", randf_range(-0.12, 0.12), 0.13)
	t.tween_property(self, "global_position", to, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "scale", Vector2.ONE, 0.08)
	t.parallel().tween_property(self, "rotation", 0.0, 0.08)
	await t.finished
	z_index = 0
	Fx.card_impact(self)


# --- Effects ----------------------------------------------------------------

func flash(amount := 1.0, duration := 0.18) -> void:
	flash_amount = amount
	create_tween().tween_property(self, "flash_amount", 0.0, duration)


## Squash-and-stretch for impacts.
func squash(strength := 1.0) -> void:
	var t := create_tween()
	t.tween_property(body, "scale", Vector2(1.0 + 0.28 * strength, 1.0 - 0.24 * strength), 0.05)
	t.tween_property(body, "scale", Vector2(1.0 - 0.08 * strength, 1.0 + 0.1 * strength), 0.09)
	t.tween_property(body, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Quick scale pop, used when scoring a card.
func pop(strength := 1.0) -> void:
	var t := create_tween()
	t.tween_property(body, "scale", Vector2.ONE * (1.0 + 0.2 * strength), 0.07)
	t.tween_property(body, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
