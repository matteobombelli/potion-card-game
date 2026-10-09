class_name NetClient
extends RefCounted
## A WebSocket connection to the multiplayer server. Call poll() every frame.

signal opened
signal closed(reason: String)
signal message(t: String, data: Dictionary)

var ws := WebSocketPeer.new()
var _was_open := false
var _active := false


func connect_to(url: String) -> Error:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	_was_open = false
	_active = true
	return ws.connect_to_url(url)


func is_open() -> bool:
	return _active and ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(t: String, payload := {}) -> void:
	if is_open():
		ws.send_text(Protocol.encode(t, payload))


func close() -> void:
	if _active:
		ws.close()


func poll() -> void:
	if not _active:
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				opened.emit()
			while ws.get_available_packet_count() > 0:
				var m := Protocol.decode(ws.get_packet().get_string_from_utf8())
				if not m.is_empty():
					message.emit(m.t, m)
		WebSocketPeer.STATE_CLOSED:
			_active = false
			var reason := ws.get_close_reason()
			if not _was_open:
				reason = "Couldn't reach the server."
			elif reason == "":
				reason = "Lost the connection to the server."
			closed.emit(reason)
