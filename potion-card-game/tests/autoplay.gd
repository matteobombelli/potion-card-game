extends Node
## Plays a full game through the real game controller (random legal clicks),
## including putting cards back, swapping and skipping swaps.
##   godot --headless --path . --scene res://tests/autoplay.tscn --fixed-fps 60 -- <players>
## Windowed, saving a screenshot every second (optionally of the main menu instead):
##   godot --path . --scene res://tests/autoplay.tscn -- <players> <shot_dir> [menu]

var game: Node
var _counts := { "swaps": 0, "skips": 0, "put_backs": 0 }
var _shot_dir := ""
var _shot_timer := 0.0
var _shot_index := 0
var _order_wait := 0.0   # in screenshot mode, linger on the order screen so it gets captured


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Session.num_players = int(args[0]) if args.size() > 0 else 4
	if args.size() > 1:
		_shot_dir = args[1]
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	else:
		Fx.hitstop_enabled = false   # hit-stop is timed in real ms; fast headless frames would stretch it
	var menu := args.size() > 2 and args[2] == "menu"
	var scene: Node = load("res://scenes/main_menu.tscn" if menu else "res://scenes/game.tscn").instantiate()
	add_child(scene)
	game = null if menu else scene


func _process(delta: float) -> void:
	_capture(delta)
	if game == null:
		return
	var state: GameState = game.state
	if state.phase == GameState.Phase.GAME_OVER:
		print("GAME OVER players=%d totals=%s winners=%s %s" % [state.num_players, state.totals, state.winners(), _counts])
		game = null
		get_tree().create_timer(3.0).timeout.connect(get_tree().quit)
		return
	if game.busy:
		return
	if game.mode == game.Mode.CHOOSE_ORDER:
		_order_wait += delta
		if _shot_dir == "" or _order_wait > 1.5:
			_order_wait = 0.0
			game.choose_order(randi() % state.order_offers[state.current_player].size())
		return
	if game.targets.is_empty():
		return

	var pick: Array = game.targets
	var mode: int = game.mode
	if mode == game.Mode.SWAP_OWN and randf() < 0.3:
		_counts.skips += 1
		game.skip_swap()
		return
	if mode == game.Mode.SWAP_OTHER:
		pick = pick.filter(func(t): return t.kind == "other_card")
		_counts.swaps += 1
	elif mode == game.Mode.PLACE:
		var held: Array = pick.filter(func(t): return t.kind == "held")
		if randf() < 0.1 and not held.is_empty():
			_counts.put_backs += 1
			pick = held
		else:
			pick = pick.filter(func(t): return t.kind != "held")
	game.click(pick.pick_random())


func _capture(delta: float) -> void:
	if _shot_dir == "":
		return
	_shot_timer += delta
	if _shot_timer >= 1.0:
		_shot_timer = 0.0
		get_viewport().get_texture().get_image().save_png("%s/shot_%03d.png" % [_shot_dir, _shot_index])
		_shot_index += 1
