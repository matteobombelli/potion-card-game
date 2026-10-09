class_name TableBackground
extends Node2D
## Dark table with a soft vignette and slowly rising potion bubbles.

const SIZE := TableLayout.SIZE


func _ready() -> void:
	z_index = -100
	var bubbles := CPUParticles2D.new()
	bubbles.amount = 46
	bubbles.lifetime = 9.0
	bubbles.preprocess = 9.0
	bubbles.texture = Fx.soft_texture()
	bubbles.position = Vector2(SIZE.x / 2.0, SIZE.y + 40)
	bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	bubbles.emission_rect_extents = Vector2(SIZE.x * 0.6, 10)
	bubbles.direction = Vector2.UP
	bubbles.spread = 8.0
	bubbles.gravity = Vector2.ZERO
	bubbles.initial_velocity_min = 50.0
	bubbles.initial_velocity_max = 150.0
	bubbles.scale_amount_min = 0.4
	bubbles.scale_amount_max = 1.6
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	g.colors = PackedColorArray(Palette.BUBBLES)
	bubbles.color_initial_ramp = g
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	bubbles.color_ramp = fade
	add_child(bubbles)


func _draw() -> void:
	var pad := 400.0
	draw_rect(Rect2(-Vector2(pad, pad), SIZE + Vector2(pad, pad) * 2), Palette.TABLE)
	# Concentric ellipses fake a soft felt spotlight.
	var steps := 14
	for i in steps:
		var t := float(i) / steps
		var r := SIZE * Vector2(0.62, 0.62) * (1.0 - t * 0.75)
		var col := Palette.FELT_EDGE.lerp(Palette.FELT_CENTER, t)
		_draw_ellipse(SIZE / 2.0, r, Color(col, 0.35))


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 64:
		var a := TAU * i / 64.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)
