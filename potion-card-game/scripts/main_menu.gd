extends TableRoot
## Title screen: the title and a few showcase cards slam in, then pick a mode:
## Tutorial, VS CPU (difficulty and number of CPUs) or Multiplayer (the lobby).

const GAME_SCENE := "res://scenes/game.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const SERVER_SCENE := "res://scenes/server.tscn"
const C := CardData.CardColor
const M := CardData.Modifier
const SHOWCASE := [
	[C.RED, 1, M.RIGHT, C.YELLOW],
	[C.YELLOW, 1, M.LEFT, C.RED],
	[C.BLACK, -2, M.GLOBAL, C.GREEN],
	[C.GREEN, 0, M.GLOBAL, C.GREEN],
	[C.BLUE, 1, M.NONE, C.BLACK],
]

var _showcase: Array[CardView] = []
var _buttons := HBoxContainer.new()   # the three modes
var _cpu_panel := VBoxContainer.new() # VS CPU settings
var _leaving := false
var _time := 0.0


func _ready() -> void:
	if Session.server_mode:
		get_tree().change_scene_to_file.call_deferred(SERVER_SCENE)
		return
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 34)
	_place_bottom(_buttons, -250, -170)
	_buttons.hide()   # not clickable until the intro has finished
	ui.add_child(_buttons)
	var tutorial := UiKit.button("TUTORIAL" if Session.tutorial_done else "TUTORIAL  (START HERE)", 38)
	tutorial.pressed.connect(_start.bind(Session.Mode.TUTORIAL))
	_buttons.add_child(tutorial)
	var cpu := UiKit.button("VS CPU", 38)
	cpu.pressed.connect(_show_cpu_panel)
	_buttons.add_child(cpu)
	var online := UiKit.button("MULTIPLAYER", 38)
	online.pressed.connect(_start.bind(Session.Mode.ONLINE))
	_buttons.add_child(online)
	_build_cpu_panel()

	var hint := Label.new()
	hint.text = "Brew a %d-card potion each round. Highest score after %d rounds wins." % [Rules.POTION_SIZE, Rules.ROUNDS]
	hint.label_settings = Fx.label_settings(24, Palette.TEXT_DIM, 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_top = -110
	hint.offset_bottom = -70
	hint.offset_left = -700
	hint.offset_right = 700
	ui.add_child(hint)

	await get_tree().create_timer(0.3).timeout
	var title := Fx.slam_title(ui, "POTION", Vector2(get_viewport().get_visible_rect().size.x / 2.0, 200), 170)
	var sub := Label.new()
	sub.text = "a card-brewing game"
	sub.label_settings = Fx.label_settings(36, Palette.TEXT_DIM, 8)
	title.add_child(sub)
	sub.position = Vector2(-sub.get_minimum_size().x / 2.0, 75)
	await get_tree().create_timer(0.35).timeout
	await _slam_showcase()
	_buttons.show()
	UiKit.fade_in(_buttons, 0.4)


func _place_bottom(c: Control, top: float, bottom: float) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	c.offset_top = top
	c.offset_bottom = bottom
	c.offset_left = -700
	c.offset_right = 700


func _build_cpu_panel() -> void:
	_cpu_panel.alignment = BoxContainer.ALIGNMENT_END
	_cpu_panel.add_theme_constant_override("separation", 16)
	_place_bottom(_cpu_panel, -470, -130)
	_cpu_panel.hide()
	ui.add_child(_cpu_panel)
	_cpu_panel.add_child(UiKit.label("DIFFICULTY", 28, Palette.TEXT_DIM, true))
	_cpu_panel.add_child(UiKit.segmented(["EASY", "MEDIUM", "OPTIMAL"], Session.difficulty,
		func(i: int): Session.difficulty = i))
	_cpu_panel.add_child(UiKit.label("OPPONENTS", 28, Palette.TEXT_DIM, true))
	_cpu_panel.add_child(UiKit.segmented(["1 CPU", "2 CPUS", "3 CPUS"], Session.num_players - 2,
		func(i: int): Session.num_players = i + 2))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	var back := UiKit.button("BACK", 34)
	back.pressed.connect(func():
		_cpu_panel.hide()
		_raise_showcase(0.0)
		_buttons.show()
		UiKit.fade_in(_buttons, 0.2))
	row.add_child(back)
	var start := UiKit.button("START", 38)
	start.pressed.connect(_start.bind(Session.Mode.CPU))
	row.add_child(start)
	_cpu_panel.add_child(row)


func _show_cpu_panel() -> void:
	_raise_showcase(-110.0)
	_buttons.hide()
	_cpu_panel.show()
	UiKit.fade_in(_cpu_panel, 0.2)


func _slam_showcase() -> void:
	for i in SHOWCASE.size():
		var spec: Array = SHOWCASE[i]
		var v := CardView.new(CardData.make(-1 - i, spec[0], spec[1], spec[2], spec[3]))
		var mid := (SHOWCASE.size() - 1) / 2.0
		var to := TableLayout.CENTER + Vector2((i - mid) * (CardArt.SIZE.x + 30.0), 40 + absf(i - mid) * 16.0)
		v.position = to + Vector2(randf_range(-300, 300), -900)
		v.rotation = randf_range(-1.0, 1.0)
		cards_layer.add_child(v)
		_showcase.append(v)
		var t := v.move_tween().set_parallel()
		t.tween_property(v, "position", to, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(v, "rotation", (i - mid) * 0.09, 0.28)
		await t.finished
		Fx.card_impact(v)
		await get_tree().create_timer(0.08).timeout


## Slides the showcase cards up to make room for the CPU settings (0 puts them back).
func _raise_showcase(dy: float) -> void:
	var mid := (_showcase.size() - 1) / 2.0
	for i in _showcase.size():
		var home := TableLayout.CENTER + Vector2((i - mid) * (CardArt.SIZE.x + 30.0), 40 + absf(i - mid) * 16.0 + dy)
		_showcase[i].move_to(home, 0.3)


func _process(delta: float) -> void:
	_time += delta
	if _leaving:
		return
	var mouse := get_global_mouse_position()
	for i in _showcase.size():
		var v := _showcase[i]
		v.set_hover(v.contains_global(mouse))
		if not v.hovered:
			v.lift = 4.0 + 4.0 * sin(_time * 2.0 + i * 0.9)


func _start(mode: Session.Mode) -> void:
	if _leaving:
		return
	_leaving = true
	Session.mode = mode
	for c in [_buttons, _cpu_panel]:
		c.create_tween().tween_property(c, "modulate:a", 0.0, 0.2)
	var last: Tween
	for v in _showcase:
		last = v.move_tween().set_parallel()
		last.tween_property(v, "position", v.position + Vector2(randf_range(-200, 200), 900), 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		last.tween_property(v, "rotation", randf_range(-2.0, 2.0), 0.45)
		await get_tree().create_timer(0.05).timeout
	if last:
		await last.finished
	get_tree().change_scene_to_file(LOBBY_SCENE if mode == Session.Mode.ONLINE else GAME_SCENE)
