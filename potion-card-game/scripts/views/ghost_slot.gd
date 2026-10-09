class_name GhostSlot
extends Node2D
## Pulsing dashed outline showing where a card can be dropped.

var side := 0
var hovered := false:
	set(v):
		if hovered == v:
			return
		hovered = v
		_tween_scale(1.08 if v else 1.0, 0.15)
var _time := 0.0
var _scale_tween: Tween


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var r := Rect2(-CardArt.SIZE / 2.0, CardArt.SIZE)
	var a := 1.0 if hovered else 0.45 + 0.25 * sin(_time * 6.0)
	if hovered:
		draw_rect(r, Color(Palette.TEXT, 0.16))
	var c := Color(Palette.TEXT, a)
	var pts := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]
	for i in 4:
		draw_dashed_line(pts[i], pts[(i + 1) % 4], c, 4.0, 12.0)
	draw_line(Vector2(-14, 0), Vector2(14, 0), c, 5.0)
	draw_line(Vector2(0, -14), Vector2(0, 14), c, 5.0)


func appear() -> void:
	show()
	scale = Vector2.ZERO
	_tween_scale(1.08 if hovered else 1.0, 0.25)


## One scale tween at a time, so appearing and hovering never fight.
func _tween_scale(target: float, duration: float) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, duration)


func contains_global(p: Vector2) -> bool:
	return visible and Rect2(-CardArt.SIZE / 2.0, CardArt.SIZE).grow(6).has_point(to_local(p))
