class_name PotionServer
extends RefCounted
## The multiplayer server: clients, the room list and message routing. Pure
## RefCounted (no nodes): server_main.gd runs it headless, Net runs one in-app
## for local testing, and tests/net_smoke.gd drives it directly.
## Call poll(delta) every frame.

const MAX_ROOMS := 200
const MAX_CLIENTS := 500
const PING_EVERY := 15.0
const DROP_AFTER := 45.0
const ROOMS_EVERY := 0.5          # room list broadcasts are throttled to this
const RATE_LIMIT := 20            # messages per second before they're dropped
const KICK_LIMIT := 100           # messages per second before the client is dropped
const MAX_CODE_TRIES := 5         # wrong room codes per CODE_TRY_WINDOW seconds
const CODE_TRY_WINDOW := 10.0

var ws := WsServer.new()
var clients := {}                 # id -> { id, name, token, room, seen, ping, rate: [count, window], tries: [times] }
var rooms := {}                   # code -> Room
var log_fn := func(msg: String): print(msg)
var _rooms_dirty := false
var _rooms_timer := 0.0
var _now := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func listen(port: int, bind := "*") -> Error:
	var err := ws.listen(port, bind)
	if err == OK:
		log_fn.call("Potion server listening on %s:%d" % [bind, port])
	return err


func stop() -> void:
	ws.stop()
	clients.clear()
	rooms.clear()


func send(id: int, t: String, payload := {}) -> void:
	ws.send(id, Protocol.encode(t, payload))


func mark_rooms_dirty() -> void:
	_rooms_dirty = true


func poll(delta: float) -> void:
	_now += delta
	for e in ws.poll(delta):
		match e.type:
			"connected": _on_connected(e.id)
			"message": _on_message(e.id, e.text)
			"closed": _on_closed(e.id)
	for room in rooms.values():
		room.poll(delta)
	for id in clients.keys():
		var c: Dictionary = clients[id]
		if _now - c.seen > DROP_AFTER:
			ws.close(id, 4000, "timed out")
			_on_closed(id)
		elif _now - c.ping > PING_EVERY:
			c.ping = _now
			send(id, "pong", { "ts": 0 })   # keeps proxies from closing idle connections
	_rooms_timer -= delta
	if _rooms_dirty and _rooms_timer <= 0.0:
		_rooms_dirty = false
		_rooms_timer = ROOMS_EVERY
		var list := _room_list()
		for c in clients.values():
			if c.room == "" and c.name != "":
				send(c.id, "rooms", { "rooms": list })


func _on_connected(id: int) -> void:
	if clients.size() >= MAX_CLIENTS:
		send(id, "error", { "code": "server_full", "msg": "The server is full. Try again later." })
		ws.close(id)
		return
	clients[id] = { "id": id, "name": "", "token": "", "room": "", "seen": _now, "ping": _now, "rate": [0, _now], "tries": [] }


func _on_closed(id: int) -> void:
	var c: Dictionary = clients.get(id, {})
	if c.is_empty():
		return
	_leave_room(c)
	clients.erase(id)


func _on_message(id: int, text: String) -> void:
	var c: Dictionary = clients.get(id, {})
	if c.is_empty():
		return
	c.seen = _now
	if _now - c.rate[1] >= 1.0:
		c.rate = [0, _now]
	c.rate[0] += 1
	if c.rate[0] > KICK_LIMIT:
		ws.close(id, 4001, "too many messages")
		_on_closed(id)
		return
	if c.rate[0] > RATE_LIMIT:
		_error(id, "rate_limited", "Slow down!")
		return
	var m := Protocol.decode(text)
	if m.is_empty():
		_error(id, "bad_message", "Couldn't read that message.")
		return
	if c.name == "" and m.t != "hello":
		_error(id, "bad_message", "Say hello first.")
		return
	match m.t:
		"hello": _hello(c, m)
		"set_name": c.name = Protocol.clean_name(m.get("name"))
		"list_rooms": send(id, "rooms", { "rooms": _room_list() })
		"create_room": _create_room(c, m)
		"join_room": _join_room(c, m)
		"leave_room":
			_leave_room(c)
			send(id, "left_room", { "reason": "left" })
			send(id, "rooms", { "rooms": _room_list() })
		"room_settings": _room_settings(c, m)
		"start_game": _start_game(c)
		"action":
			var room: Room = rooms.get(c.room)
			if room and m.get("action") is Dictionary and int(m.get("game_id", -1)) == room.game_id:
				room.handle_action(id, m.action)
		"ack_round":
			var room: Room = rooms.get(c.room)
			if room:
				room.handle_ack(id, int(m.get("game_id", -1)), int(m.get("round", -1)))
		"rematch":
			var room: Room = rooms.get(c.room)
			if room:
				room.set_rematch(id, bool(m.get("ready", false)))
		"ping": send(id, "pong", { "ts": m.get("ts", 0) })
		_: _error(id, "bad_message", "Unknown message '%s'." % m.t)


func _hello(c: Dictionary, m: Dictionary) -> void:
	if int(m.get("v", -1)) != Protocol.VERSION:
		_error(c.id, "bad_version", "Your game is version %s but the server is version %d. Please update." % [m.get("v"), Protocol.VERSION])
		ws.close(c.id)
		return
	c.name = Protocol.clean_name(m.get("name"))
	c.token = str(m.get("token", "")).left(64)
	send(c.id, "welcome", { "id": c.id, "name": c.name, "v": Protocol.VERSION })
	send(c.id, "rooms", { "rooms": _room_list() })


func _create_room(c: Dictionary, m: Dictionary) -> void:
	if c.room != "":
		_leave_room(c)
	if rooms.size() >= MAX_ROOMS:
		_error(c.id, "server_full", "Too many rooms right now. Join one instead!")
		return
	var code := _new_code()
	var room := Room.new(self, code, Protocol.clean_name(m.get("name"), "%s's room" % c.name.left(9)),
		int(m.get("cap", 4)), bool(m.get("private", false)))
	rooms[code] = room
	c.room = code
	room.add_member(c.id, c.name)
	log_fn.call("Room %s created by %s (%s, %d players)" % [code, c.name, "private" if room.private else "public", room.cap])
	mark_rooms_dirty()


func _join_room(c: Dictionary, m: Dictionary) -> void:
	var code := Protocol.clean_code(m.get("code"))
	if code == c.room:
		return
	c.tries = c.tries.filter(func(t): return _now - t < CODE_TRY_WINDOW)
	if c.tries.size() >= MAX_CODE_TRIES:
		_error(c.id, "too_many_tries", "Too many wrong codes. Wait a few seconds.")
		return
	var room: Room = rooms.get(code)
	if room == null:
		c.tries.append(_now)
		_error(c.id, "no_room", "There's no room with code %s." % code)
		return
	if room.state == Room.State.PLAYING:
		_error(c.id, "in_game", "That game has already started.")
		return
	if room.is_full():
		_error(c.id, "room_full", "That room is full.")
		return
	_leave_room(c)
	c.room = code
	room.add_member(c.id, c.name)
	mark_rooms_dirty()


func _leave_room(c: Dictionary) -> void:
	var room: Room = rooms.get(c.room)
	c.room = ""
	if room == null:
		return
	room.remove_member(c.id)
	if room.members.is_empty():
		rooms.erase(room.code)
		log_fn.call("Room %s closed" % room.code)
	mark_rooms_dirty()


func _room_settings(c: Dictionary, m: Dictionary) -> void:
	var room: Room = rooms.get(c.room)
	if room == null or room.host_id != c.id or room.state != Room.State.LOBBY:
		_error(c.id, "not_host", "Only the host can change the room before the game.")
		return
	if m.has("name"):
		room.name = Protocol.clean_name(m.name, room.name)
	if m.has("cap"):
		room.cap = clampi(int(m.cap), maxi(2, room.members.size()), 4)
	if m.has("private"):
		room.private = bool(m.private)
	room.broadcast_info()
	mark_rooms_dirty()


func _start_game(c: Dictionary) -> void:
	var room: Room = rooms.get(c.room)
	if room == null or room.host_id != c.id or room.state == Room.State.PLAYING:
		_error(c.id, "not_host", "Only the host can start the game.")
		return
	if room.members.size() < 2:
		_error(c.id, "not_enough_players", "You need at least 2 players.")
		return
	room.start_game()
	log_fn.call("Room %s started a game with %d players" % [room.code, room.members.size()])
	mark_rooms_dirty()


func _room_list() -> Array:
	var list: Array = rooms.values().map(func(r): return r.public_info())
	var order := { "lobby": 0, "finished": 1, "playing": 2 }   # joinable rooms first
	list.sort_custom(func(a, b): return order[a.state] < order[b.state] if a.state != b.state else a.name < b.name)
	return list


func _new_code() -> String:
	while true:
		var code := ""
		for i in Protocol.CODE_LENGTH:
			code += Protocol.CODE_LETTERS[_rng.randi_range(0, Protocol.CODE_LETTERS.length() - 1)]
		if not rooms.has(code):
			return code
	return ""


func _error(id: int, code: String, msg: String) -> void:
	send(id, "error", { "code": code, "msg": msg })
