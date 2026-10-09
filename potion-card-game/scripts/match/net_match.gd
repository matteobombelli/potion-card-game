class_name NetMatch
extends Match
## A game on the multiplayer server. Moves go to the server; its game_event
## messages (with your redacted snapshot) come back as `event`.

var game_id := -1
var _start := {}
var _round := 0


func _init(start: Dictionary) -> void:
	_start = start
	game_id = int(start.get("game_id", -1))
	local_player = int(start.get("you", 0))
	for s in start.get("seats", []).size():
		var seat: Dictionary = start.seats[s]
		seat_names.append(str(seat.get("name", "Player")))
		seat_kinds.append("you" if s == local_player else str(seat.get("kind", "human")))


func begin() -> void:
	started.emit.call_deferred(_start.get("snapshot", {}))
	Net.attach.call_deferred(self)   # after `started`, then any messages that arrived meanwhile


## Messages from the server, routed here by Net.
func handle(t: String, data: Dictionary) -> void:
	if t != "room" and int(data.get("game_id", -1)) != game_id:
		return
	match t:
		"game_event":
			var snap: Dictionary = data.get("snapshot", {})
			_round = int(snap.get("round", _round))
			event.emit(data.get("action", {}), snap)
		"rejected":
			rejected.emit(data.get("snapshot", {}))
		"seat_update":
			var s := int(data.get("seat", -1))
			if s >= 0 and s < seat_names.size():
				seat_names[s] = str(data.get("name", seat_names[s]))
				seat_kinds[s] = str(data.get("kind", seat_kinds[s]))
				seats_changed.emit()
		"room":
			room_changed.emit(data)


func submit(action: Dictionary) -> void:
	Net.send("action", { "game_id": game_id, "action": action })


func scores_shown() -> void:
	Net.send("ack_round", { "game_id": game_id, "round": _round })


func leave() -> void:
	Net.send("leave_room")
	detach_from_net()


func detach_from_net() -> void:
	Net.detach(self)


func _exit_tree() -> void:
	Net.detach(self)
