extends Node
## Plays full games through the real game controller: random legal clicks for
## your seat (putting cards back, swapping, skipping), CPUs for the others.
##   godot --headless --path . --scene res://tests/autoplay.tscn --fixed-fps 60 -- cpu <cpus> <easy|medium|optimal> --fast
##   godot --headless --path . --scene res://tests/autoplay.tscn --fixed-fps 60 -- tutorial --fast
## Online: an in-app server and a bot opponent on its own connection; plays a game,
## a rematch, and the opponent drops out halfway through the second one:
##   godot --headless --path . --scene res://tests/autoplay.tscn --fixed-fps 60 -- online
## Windowed, saving a screenshot every second (or of the main menu instead):
##   godot --path . --scene res://tests/autoplay.tscn -- cpu 3 medium shots=<dir>
##   godot --path . --scene res://tests/autoplay.tscn -- menu shots=<dir>

var game: Node
var _counts := { "swaps": 0, "skips": 0, "put_backs": 0, "tips": 0 }
var _shot_dir := ""
var _shot_timer := 0.0
var _shot_index := 0
var _linger := 0.0
var _timeout := 600.0


func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a): return not a.begins_with("--"))
	for a in args:
		if a.begins_with("shots="):
			_shot_dir = a.trim_prefix("shots=")
			DirAccess.make_dir_recursive_absolute(_shot_dir)
	args = args.filter(func(a): return not a.begins_with("shots="))
	if _shot_dir == "":
		Fx.hitstop_enabled = false   # hit-stop is timed in real ms; fast headless frames would stretch it
	var kind: String = args[0] if args.size() > 0 else "cpu"
	if kind == "menu":
		add_child(load("res://scenes/main_menu.tscn").instantiate())
		return
	if kind == "online":
		_start_online()
		return
	if kind == "tutorial":
		Session.mode = Session.Mode.TUTORIAL
	else:
		Session.mode = Session.Mode.CPU
		Session.num_players = (int(args[1]) if args.size() > 1 else 3) + 1
		Session.difficulty = ["easy", "medium", "optimal"].find(args[2] if args.size() > 2 else "medium") as Bot.Difficulty
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)



# --- Online ---------------------------------------------------------------------

var _online := false
var _games_played := 0
var _opponent: NetClient
var _opp := { "game_id": -1, "seat": -1, "snap": {}, "acted": -1, "acked": -1, "cool": 0.0 }
var _opp_bot := MediumBot.new()


func _start_online() -> void:
	_online = true
	Session.mode = Session.Mode.ONLINE
	Session.player_name = "Auto"
	Net.switch_scenes = false
	var port := randi_range(20000, 40000)
	if Net.start_local_server(port) != OK:
		push_error("couldn't start the local server")
		get_tree().quit(1)
		return
	Net.local_server.log_fn = func(_m): pass
	var url := "ws://127.0.0.1:%d" % port
	Net.connected.connect(func(): Net.send("create_room", { "name": "Autoplay", "cap": 2, "private": true }), CONNECT_ONE_SHOT)
	Net.room_changed.connect(_on_online_room)
	Net.game_started.connect(_on_online_game)
	Net.connect_to_server(url)
	_opponent = NetClient.new()
	_opponent.opened.connect(func(): _opponent.send("hello", { "v": Protocol.VERSION, "name": "Opponent", "token": "opp" }))
	_opponent.message.connect(_on_opponent_message)
	_opponent.connect_to(url)


func _on_online_room() -> void:
	var r := Net.room
	if r.is_empty():
		return
	if r.state == "lobby" and r.members.size() == 1 and _opponent.is_open():
		_opponent.send("join_room", { "code": r.code })
	elif r.state == "lobby" and r.members.size() == 2:
		Net.send("start_game")
	elif r.state == "finished" and _games_played == 1 and r.members.size() == 2:
		_opponent.send("rematch", { "ready": true })


func _on_online_game() -> void:
	if game:
		game.queue_free()
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)


func _on_opponent_message(t: String, d: Dictionary) -> void:
	match t:
		"game_start":
			_opp.game_id = int(d.game_id)
			_opp.seat = int(d.you)
			_opp.snap = d.snapshot
			_opp.acted = -1
			_opp.acked = -1
		"game_event":
			if int(d.game_id) == _opp.game_id and int(d.snapshot.seq) > int(_opp.snap.get("seq", -1)):
				_opp.snap = d.snapshot


## The opponent plays its seat with the Medium bot, and drops out mid-way through game 2.
func _poll_opponent(delta: float) -> void:
	if _opponent == null:
		return
	_opponent.poll()
	_opp.cool -= delta
	if _opp.snap.is_empty() or _opp.cool > 0.0 or not _opponent.is_open():
		return
	var view := GameState.from_snapshot(_opp.snap)
	if _opp.game_id >= 2 and view.round_index >= 2 and view.phase != GameState.Phase.GAME_OVER:
		print("Opponent drops out")
		_opponent.close()
		return
	if view.phase == GameState.Phase.ROUND_OVER:
		if _opp.acked != view.round_index:
			_opp.acked = view.round_index
			_opponent.send("ack_round", { "game_id": _opp.game_id, "round": view.round_index })
		return
	if view.legal_actions(_opp.seat).is_empty() or _opp.acted == int(_opp.snap.seq):
		return
	_opp.acted = int(_opp.snap.seq)
	_opp.cool = 0.3
	_opponent.send("action", { "game_id": _opp.game_id, "action": _opp_bot.decide(view, _opp.seat) })


# --- Driving your seat -------------------------------------------------------------

func _process(delta: float) -> void:
	_capture(delta)
	_timeout -= delta
	if _online:
		_poll_opponent(delta)
	if game == null or not is_instance_valid(game):
		return
	if _timeout < 0:
		push_error("autoplay timed out in mode %d phase %d" % [game.mode, game.state.phase if game.state else -1])
		get_tree().quit(1)
		return
	var state: GameState = game.state
	if state == null:
		return
	if state.phase == GameState.Phase.GAME_OVER and game._game_over != null:
		if _online and _games_played == 1 and int(Session.online_start.game_id) == 1:
			return
		print("GAME OVER mode=%d players=%d totals=%s winners=%s names=%s %s" % [Session.mode, state.num_players, state.totals,
			state.winners(), game.game_match.seat_names, _counts])
		if _online and int(Session.online_start.game_id) == 1:
			if _games_played == 0:
				_games_played = 1
				game._game_over.rematch.emit(true)   # as if REMATCH was clicked
			return   # wait for the rematch to start
		game = null
		get_tree().create_timer(3.0 if _shot_dir != "" else 0.5).timeout.connect(get_tree().quit)
		return
	if game.director and game.director.tip.blocking():
		if game.director.waiting_for_next():
			_counts.tips += 1
			if OS.get_cmdline_user_args().has("verbose"):
				print("TIP: ", game.director.tip._text.text.left(70))
			game.director.next()
		return
	if game.busy:
		return
	# Pause before each click: in screenshot mode so choices get captured, and in the
	# tutorial so its tip has a moment to appear, as it would for a player.
	var pause := 0.8 if _shot_dir != "" else (0.3 if game.director and game.director.active() else 0.0)
	_linger += delta
	if _linger < pause:
		return
	_linger = 0.0
	if game.mode == game.Mode.CHOOSE_ORDER:
		var n: int = state.order_offers[game.me].size()
		var allowed: int = game.director.allowed_order() if game.director else -1
		game.choose_order(allowed if allowed >= 0 else randi() % n)
		return
	if game.targets.is_empty():
		return

	var pick: Array = game.targets
	var mode: int = game.mode
	var tutorial: bool = game.director != null and game.director.active()
	if mode == game.Mode.SWAP_OWN and not tutorial and randf() < 0.3:
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
	if pick.is_empty():
		return
	game.click(pick.pick_random())


func _capture(delta: float) -> void:
	if _shot_dir == "":
		return
	_shot_timer += delta
	if _shot_timer >= 1.0:
		_shot_timer = 0.0
		get_viewport().get_texture().get_image().save_png("%s/shot_%03d.png" % [_shot_dir, _shot_index])
		_shot_index += 1
