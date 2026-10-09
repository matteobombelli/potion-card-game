extends SceneTree
## Multiplayer smoke test: an in-process server and three WebSocket clients.
##   godot --headless --path . -s res://tests/net_smoke.gd
## Covers private rooms and codes, a full game played through the protocol by
## bots (checking no secret ever reaches the wrong client), a rematch, a player
## dropping mid-game (a CPU takes over) and the host leaving.

const TIMEOUT := 120.0

var _fails := 0
var _passes := 0
var server := PotionServer.new()
var port := 0
var _elapsed := 0.0


class TestClient:
	var label: String
	var net := NetClient.new()
	var inbox: Array = []        # [t, data] not yet looked at
	var me := {}
	var room := {}
	var rooms: Array = []
	var errors: Array = []
	var game_id := -1
	var seat := -1
	var snap := {}
	var acted_seq := -1
	var acked_round := -1
	var seat_updates: Array = []
	var leaks: Array = []
	var bot := MediumBot.new()
	var cooldown := 0.0          # stay under the server's rate limit, like a human would

	func _init(p_label: String) -> void:
		label = p_label
		net.opened.connect(func(): net.send("hello", { "v": Protocol.VERSION, "name": label, "token": label }))
		net.message.connect(_on_message)

	func _on_message(t: String, d: Dictionary) -> void:
		match t:
			"welcome": me = d
			"room": room = d
			"left_room": room = {}
			"rooms": rooms = d.rooms
			"error": errors.append(d.code)
			"seat_update": seat_updates.append(d)
			"game_start":
				game_id = int(d.game_id)
				seat = int(d.you)
				snap = d.snapshot
				acted_seq = -1
				acked_round = -1
			"game_event":
				if int(d.game_id) == game_id and int(d.snapshot.seq) > int(snap.get("seq", -1)):
					snap = d.snapshot
				_check_secrets(d.action, d.snapshot)
		inbox.append([t, d])

	## Nothing secret may reach this client.
	func _check_secrets(action: Dictionary, s: Dictionary) -> void:
		if s.has("rng") or s.has("returns") or s.has("setup"):
			leaks.append("rng or private lists in snapshot")
		for d in s.decks:
			if d.has("cards"):
				leaks.append("deck contents")
		var revealed := int(s.phase) == GameState.Phase.ROUND_OVER or int(s.phase) == GameState.Phase.GAME_OVER
		for p in int(s.n):
			if p == seat:
				continue
			if s.offers[p] is Array:
				leaks.append("another player's offers")
			if s.orders[p] is Array and not revealed:
				leaks.append("another player's order")
		if action.get("type") == "choose_order" and int(action.player) != seat and action.has("offer"):
			leaks.append("another player's order choice")

	## Plays our seat with the Medium bot, and acks rounds.
	func play(dt: float) -> void:
		cooldown -= dt
		if snap.is_empty() or game_id < 0 or cooldown > 0.0:
			return
		var view := GameState.from_snapshot(snap)
		var seq := int(snap.seq)
		if view.phase == GameState.Phase.ROUND_OVER:
			if acked_round != view.round_index:
				acked_round = view.round_index
				net.send("ack_round", { "game_id": game_id, "round": view.round_index })
			return
		if view.legal_actions(seat).is_empty() or acted_seq == seq:
			return
		acted_seq = seq
		cooldown = 0.1
		net.send("action", { "game_id": game_id, "action": bot.decide(view, seat) })

	func phase() -> int:
		return int(snap.get("phase", -1))


func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func _initialize() -> void:
	server.log_fn = func(_m): pass
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for attempt in 10:
		port = rng.randi_range(20000, 40000)
		if server.listen(port, "127.0.0.1") == OK:
			break
	run.call_deferred()


## Polls everything until `cond` is true (or fails after `limit` seconds).
func wait_for(cond: Callable, what: String, clients: Array, limit := 30.0) -> bool:
	var t := 0.0
	while not cond.call():
		await process_frame
		var dt := 1.0 / 60.0
		t += dt
		_elapsed += dt
		server.poll(dt)
		for c in clients:
			c.net.poll()
			c.play(dt)
		if t > limit or _elapsed > TIMEOUT:
			for x in clients:
				var sn: Dictionary = x.snap
				print("  %s seat=%d game=%d phase=%s round=%s current=%s seq=%s acted=%d errors=%s" % [x.label, x.seat, x.game_id,
					sn.get("phase"), sn.get("round"), sn.get("current"), sn.get("seq"), x.acted_seq, x.errors])
			check(false, "timed out waiting for: " + what)
			return false
	check(true, what)
	return true


func run() -> void:
	var url := "ws://127.0.0.1:%d" % port
	var a := TestClient.new("Alice")
	var b := TestClient.new("Bob")
	var c := TestClient.new("Cleo")
	var all := [a, b, c]
	for x in all:
		x.net.connect_to(url)
	await wait_for(func(): return all.all(func(x): return not x.me.is_empty()), "everyone connects", all)

	# A private room is listed without its code; a wrong code fails, the right one works.
	a.net.send("create_room", { "name": "Test room", "cap": 3, "private": true })
	await wait_for(func(): return not a.room.is_empty(), "room created", all)
	var code: String = a.room.code
	await wait_for(func(): return b.rooms.any(func(r): return r.name == "Test room"), "room listed", all)
	var listed: Dictionary = b.rooms.filter(func(r): return r.name == "Test room")[0]
	check(listed.private and listed.code == null, "private room is listed without its code")
	b.net.send("join_room", { "code": "ZZZZZ" })
	await wait_for(func(): return b.errors.has("no_room"), "wrong code is refused", all)
	b.net.send("join_room", { "code": code.to_lower() })
	await wait_for(func(): return a.room.get("members", []).size() == 2, "joined with the code", all)
	b.net.send("start_game")
	await wait_for(func(): return b.errors.has("not_host"), "only the host can start", all)

	# Game 1: both play to the end through the protocol.
	a.net.send("start_game")
	await wait_for(func(): return a.game_id == 1 and b.game_id == 1, "game starts for both", all)
	check(a.seat != b.seat, "different seats")
	await wait_for(func(): return a.phase() == GameState.Phase.GAME_OVER and b.phase() == GameState.Phase.GAME_OVER,
		"game 1 reaches game over", [a, b, c], 60.0)
	check(a.snap.totals == b.snap.totals, "both see the same final scores")

	# Rematch: both vote, a new game starts.
	a.net.send("rematch", { "ready": true })
	b.net.send("rematch", { "ready": true })
	await wait_for(func(): return a.game_id == 2 and b.game_id == 2, "rematch starts game 2", all)

	# Game 2: Bob drops in round 2, a CPU takes his seat and the game still ends.
	await wait_for(func(): return int(b.snap.get("round", 0)) >= 1, "game 2 reaches round 2", [a, b, c], 60.0)
	b.net.close()
	await wait_for(func(): return a.seat_updates.any(func(u): return u.kind == "bot"), "a CPU takes the dropped seat", [a, c])
	await wait_for(func(): return a.phase() == GameState.Phase.GAME_OVER, "game 2 finishes with the CPU", [a, c], 90.0)

	# Cleo joins the finished room; when Alice leaves, Cleo becomes host.
	c.net.send("join_room", { "code": code })
	await wait_for(func(): return not c.room.is_empty(), "joining a finished room works", [a, c])
	a.net.send("leave_room")
	await wait_for(func(): return c.room.get("host", -1) == c.me.id, "host passes on when the host leaves", [a, c])

	for x in all:
		check(x.leaks.is_empty(), "%s saw no secrets %s" % [x.label, x.leaks])
	for x in all:
		x.net.close()
	server.stop()
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
