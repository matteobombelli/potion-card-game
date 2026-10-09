extends Node
## Autoload "Net": the client's connection to the multiplayer server, kept
## across scene changes. Caches what the lobby shows (rooms, your room) and
## switches to the game when the server starts one. Can also run a server
## inside the app (HOST LOCAL SERVER) so two windows can test on one machine.

signal connected
signal disconnected(reason: String)
signal rooms_changed
signal room_changed
signal server_error(code: String, msg: String)
signal game_started

const GAME_SCENE := "res://scenes/game.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const PING_EVERY := 10.0

var switch_scenes := true   # tests turn this off and load the game scene themselves
var client := NetClient.new()
var local_server: PotionServer
var me := {}          # the server's welcome: id, name
var rooms: Array = []
var room := {}        # the room you're in ({} if none)
var _match: NetMatch  # the game being played, which gets the game messages
var _queued: Array = []   # game messages that arrived before the game scene was ready
var _ping := 0.0


func _ready() -> void:
	client.opened.connect(_on_opened)
	client.closed.connect(_on_closed)
	client.message.connect(_on_message)


func is_online() -> bool:
	return client.is_open() and not me.is_empty()


func connect_to_server(url: String) -> Error:
	me = {}
	room = {}
	rooms = []
	return client.connect_to(url)


func disconnect_from_server() -> void:
	client.close()


## Starts a server inside this app on localhost (for testing with a second window).
func start_local_server(port := Session.DEFAULT_PORT) -> Error:
	if local_server:
		return OK
	local_server = PotionServer.new()
	var err := local_server.listen(port, "127.0.0.1")
	if err != OK:
		local_server = null
	return err


func send(t: String, payload := {}) -> void:
	client.send(t, payload)


func attach(m: NetMatch) -> void:
	_match = m
	for q in _queued:
		m.handle(q[0], q[1])
	_queued.clear()


func detach(m: NetMatch) -> void:
	if _match == m:
		_match = null


func _process(delta: float) -> void:
	if local_server:
		local_server.poll(delta)
	client.poll()
	if client.is_open():
		_ping -= delta
		if _ping <= 0.0:
			_ping = PING_EVERY
			send("ping", { "ts": Time.get_ticks_msec() })


func _on_opened() -> void:
	send("hello", { "v": Protocol.VERSION, "name": Session.player_name, "token": Session.token })


func _on_closed(reason: String) -> void:
	me = {}
	room = {}
	if _match:
		_match.closed.emit(reason)
	disconnected.emit(reason)


func _on_message(t: String, data: Dictionary) -> void:
	match t:
		"welcome":
			me = data
			connected.emit()
		"rooms":
			rooms = data.get("rooms", [])
			rooms_changed.emit()
		"room":
			room = data
			room_changed.emit()
			if _match:
				_match.handle(t, data)
		"left_room":
			room = {}
			room_changed.emit()
		"error":
			server_error.emit(str(data.get("code", "")), str(data.get("msg", "")))
		"game_start":
			Session.mode = Session.Mode.ONLINE
			Session.online_start = data
			_queued.clear()
			if _match:
				_match.detach_from_net()
			if switch_scenes:
				get_tree().change_scene_to_file(GAME_SCENE)
			game_started.emit()
		"game_event", "rejected", "seat_update":
			if _match:
				_match.handle(t, data)
			else:
				_queued.append([t, data])
