class_name MiddleDeckView
extends Node2D
## A face-up middle deck: card backs peeking out underneath, the takeable top card
## and a count badge. The top card can be lifted off and put back before a move is
## committed; set_contents() then shows what the rules engine says is left.

const LAYER_STEP := 3.0
const MAX_LAYERS := 6

var top_view: CardView
var count := 0
var _count_label := Label.new()


func _init() -> void:
	material = CardArt.make_material(CardArt.BACK_TINT)
	_count_label.label_settings = Fx.label_settings(26, Palette.TEXT, 10)
	_count_label.z_index = 2  # the badge sits over the top card's corner
	add_child(_count_label)


## Shows the deck as the rules engine has it: `remaining` cards with `top` face up.
func set_contents(remaining: int, top: CardData, animated := true) -> void:
	count = remaining
	_count_label.text = str(remaining) if remaining > 0 else ""
	var sz := _count_label.get_minimum_size()
	_count_label.position = CardArt.SIZE / 2.0 + Vector2(4, _layers() * LAYER_STEP - sz.y + 6)
	queue_redraw()
	if top_view:
		top_view.queue_free()
		top_view = null
	if top == null:
		return
	top_view = CardView.new(top)
	add_child(top_view)
	if animated:
		top_view.scale = Vector2(0.0, 1.0)
		top_view.create_tween().tween_property(top_view, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Detaches the top card so it can be held; the stack underneath stays as it is.
func lift_top(new_parent: Node) -> CardView:
	var v := top_view
	top_view = null
	v.reparent(new_parent, true)
	return v


## Returns a lifted card to the top of this deck.
func put_back(v: CardView) -> void:
	v.reparent(self, true)
	top_view = v
	v.move_to(global_position, 0.25)


func _layers() -> int:
	return mini(maxi(count - 1, 0), MAX_LAYERS)


func _draw() -> void:
	var size := CardArt.SIZE
	if count == 0:
		draw_rect(Rect2(-size / 2.0, size), Color(Palette.TEXT, 0.25), false, 3.0)
		return
	# Card backs peeking out under the top card, deepest first.
	for i in range(_layers(), -1, -1):
		draw_texture_rect(CardArt.BACKING, Rect2(-size / 2.0 + Vector2(0, i * LAYER_STEP), size), false)
