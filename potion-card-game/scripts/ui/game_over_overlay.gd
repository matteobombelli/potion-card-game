class_name GameOverOverlay
extends CanvasLayer
## Winner title, final standings and the Play again / Main menu buttons.

signal play_again
signal main_menu

const PLACES := ["1ST", "2ND", "3RD", "4TH", "5TH", "6TH"]

var _totals: Array
var _winners: Array


func _init(totals: Array, winners: Array) -> void:
	layer = 5
	_totals = totals
	_winners = winners


func _ready() -> void:
	var dim := UiKit.dim(0.7)
	add_child(dim)
	UiKit.fade_in(dim, 0.5)

	var title: String
	if _winners.size() == 1:
		title = "PLAYER %d WINS!" % (_winners[0] + 1)
	else:
		title = "TIE: %s!" % " & ".join(_winners.map(func(w): return "P%d" % (w + 1)))
	Fx.slam_title(self, title, Vector2(get_viewport().get_visible_rect().size.x / 2.0, 260))

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 170)
	box.add_child(spacer)

	var ranking: Array = range(_totals.size())
	ranking.sort_custom(func(a, b): return _totals[a] > _totals[b])
	for r in ranking.size():
		var p: int = ranking[r]
		var l := Label.new()
		l.text = "%s   PLAYER %d   %d pts" % [PLACES[r], p + 1, _totals[p]]
		l.label_settings = Fx.label_settings(44 if r == 0 else 36, Palette.SCORE if _winners.has(p) else Palette.TEXT, 9)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		UiKit.fade_in(l, 0.25, 0.3 + 0.25 * r)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	box.add_child(buttons)
	var again := UiKit.button("PLAY AGAIN")
	again.pressed.connect(play_again.emit)
	buttons.add_child(again)
	var menu := UiKit.button("MAIN MENU")
	menu.pressed.connect(main_menu.emit)
	buttons.add_child(menu)
	UiKit.fade_in(buttons, 0.4, 0.3 + 0.25 * ranking.size())

	var w := get_viewport().get_visible_rect().size
	for k in 2:
		var t := create_tween()
		t.tween_interval(0.2 + 0.7 * k)
		t.tween_callback(func():
			Fx.confetti(Vector2(150, w.y + 20), Palette.CONFETTI, 50, 1300.0, self)
			Fx.confetti(Vector2(w.x - 150, w.y + 20), Palette.CONFETTI, 50, 1300.0, self))
