class_name Shockwave
extends Node2D
## Expanding ring drawn with draw_arc; animated by Fx.ring().

var color := Color.WHITE
var width := 10.0
var radius := 4.0:
	set(v):
		radius = v
		queue_redraw()
var alpha := 1.0:
	set(v):
		alpha = v
		queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, alpha), width * alpha + 1.0, true)
