class_name WsServer
extends RefCounted
## A plain WebSocket server on top of TCPServer (TLS is left to a reverse proxy
## such as Caddy). Call poll() every frame; it returns what happened since:
## [{ type: "connected" | "message" | "closed", id, text }].

const HANDSHAKE_TIMEOUT := 5.0

var _tcp := TCPServer.new()
var _peers := {}    # id -> { ws: WebSocketPeer, open: bool, age: float }
var _next_id := 1


func listen(port: int, bind := "*") -> Error:
	return _tcp.listen(port, bind)


func is_listening() -> bool:
	return _tcp.is_listening()


func stop() -> void:
	for id in _peers:
		_peers[id].ws.close()
	_peers.clear()
	_tcp.stop()


func peer_count() -> int:
	return _peers.size()


func send(id: int, text: String) -> void:
	var p: Dictionary = _peers.get(id, {})
	if not p.is_empty() and p.open:
		p.ws.send_text(text)


func close(id: int, code := 1000, reason := "") -> void:
	var p: Dictionary = _peers.get(id, {})
	if not p.is_empty():
		p.ws.close(code, reason)


func poll(delta: float) -> Array:
	var out: Array = []
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = Protocol.MAX_MESSAGE * 4
		ws.outbound_buffer_size = 1 << 20
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_peers[_next_id] = { "ws": ws, "open": false, "age": 0.0 }
			_next_id += 1
	for id in _peers.keys():
		var p: Dictionary = _peers[id]
		var ws: WebSocketPeer = p.ws
		ws.poll()
		p.age += delta
		match ws.get_ready_state():
			WebSocketPeer.STATE_CONNECTING:
				if p.age > HANDSHAKE_TIMEOUT:
					_peers.erase(id)
			WebSocketPeer.STATE_OPEN:
				if not p.open:
					p.open = true
					out.append({ "type": "connected", "id": id })
				while ws.get_available_packet_count() > 0:
					var pkt := ws.get_packet()
					if ws.was_string_packet():
						out.append({ "type": "message", "id": id, "text": pkt.get_string_from_utf8() })
			WebSocketPeer.STATE_CLOSED:
				if p.open:
					out.append({ "type": "closed", "id": id })
				_peers.erase(id)
	return out
