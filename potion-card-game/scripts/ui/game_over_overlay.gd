class_name GameOverOverlay
extends CanvasLayer
## Winner title, final standings and the buttons for what's next, which depend
## on the mode: Play again (CPU), Play vs CPU (tutorial) or Rematch votes (online).

signal play_again
signal play_cpu
signal main_menu
signal rematch(ready: bool)

const PLACES := ["1ST", "2ND", "3RD", "4TH", "5TH", "6TH"]

var _totals: Array
var _winners: Array
var _names: Array
var _me: int
var _mode: int
var _rematch_label: Label
var _rematch_button: Button


func _init(totals: Array, winners: Array, names: Array, me: int, mode: int) -> void:
	layer = 5
	_totals = totals
	_winners = winners
	_names = names
	_me = me
	_mode = mode


func _ready() -> void:
	var dim := UiKit.dim(0.7)
	add_child(dim)
	UiKit.fade_in(dim, 0.5)

	var title: String
	if _mode == Session.Mode.TUTORIAL:
		title = "TUTORIAL COMPLETE!"
	elif _winners.size() == 1:
		title = "YOU WIN!" if _winners[0] == _me else "%s WINS!" % _names[_winners[0]].to_upper()
	else:
		title = "TIE: %s!" % " & ".join(_winners.map(func(w): return _names[w].to_upper()))
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
		l.text = "%s   %s   %d pts" % [PLACES[r], _names[p].to_upper(), _totals[p]]
		l.label_settings = Fx.label_settings(44 if r == 0 else 36, Palette.SCORE if _winners.has(p) else Palette.TEXT, 9)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		UiKit.fade_in(l, 0.25, 0.3 + 0.25 * r)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	box.add_child(buttons)
	match _mode:
		Session.Mode.CPU:
			_add_button(buttons, "PLAY AGAIN", play_again.emit)
			_add_button(buttons, "MAIN MENU", main_menu.emit)
		Session.Mode.TUTORIAL:
			_add_button(buttons, "PLAY VS CPU", play_cpu.emit)
			_add_button(buttons, "MAIN MENU", main_menu.emit)
		Session.Mode.ONLINE:
			_rematch_button = UiKit.toggle("CANCEL REMATCH", "REMATCH", false, func(on: bool): rematch.emit(on))
			buttons.add_child(_rematch_button)
			_add_button(buttons, "LEAVE ROOM", main_menu.emit)
			_rematch_label = UiKit.label("", 28, Palette.TEXT_DIM, true)
	UiKit.fade_in(buttons, 0.4, 0.3 + 0.25 * ranking.size())
	if _rematch_label:
		box.add_child(_rematch_label)

	var w := get_viewport().get_visible_rect().size
	for k in 2:
		var t := create_tween()
		t.tween_interval(0.2 + 0.7 * k)
		t.tween_callback(func():
			Fx.confetti(Vector2(150, w.y + 20), Palette.CONFETTI, 50, 1300.0, self)
			Fx.confetti(Vector2(w.x - 150, w.y + 20), Palette.CONFETTI, 50, 1300.0, self))


## Online: shows how many players in the room want a rematch.
func set_rematch_votes(ready: int, total: int, others_left := false) -> void:
	if _rematch_label == null:
		return
	var text := "Rematch: %d / %d ready" % [ready, total]
	if total < 2:
		text = "Everyone else left. Wait for someone to join, or leave the room."
	elif others_left:
		text += "  (players who left are dropped)"
	_rematch_label.text = text


func _add_button(row: Container, text: String, on_press: Callable) -> void:
	var b := UiKit.button(text)
	b.pressed.connect(on_press)
	row.add_child(b)
