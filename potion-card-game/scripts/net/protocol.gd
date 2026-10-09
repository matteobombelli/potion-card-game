class_name Protocol
extends RefCounted
## The multiplayer message format: one JSON object per WebSocket text frame,
## {"t": type, ...fields}. Bump VERSION when messages change incompatibly; the
## server turns away clients with another version.
##
## Client -> server
##   hello        v, name, token
##   set_name     name
##   list_rooms
##   create_room  name, cap (2-4), private (bool)
##   join_room    code
##   leave_room
##   room_settings  name?, cap?, private?        (host, before the game)
##   start_game                                   (host, 2+ players)
##   action       game_id, action {type, deck, side, offer, ...}   (player is filled in by the server)
##   ack_round    game_id, round                  (done showing the scores)
##   rematch      ready (bool)
##   ping         ts
##
## Server -> client
##   welcome      id, name, v
##   error        code, msg     codes: bad_version, bad_message, no_room, room_full, in_game,
##                              not_host, not_enough_players, rate_limited, server_full, too_many_tries
##   rooms        rooms: [{code (null if private), name, private, players, cap, state, host_name}]
##   room         code, name, cap, private, host, state, you, members: [{id, name, rematch}]
##   left_room    reason
##   game_start   game_id, you (seat), seats: [{name, kind: human|bot}], snapshot
##   game_event   game_id, action, snapshot      (action is redacted; snapshot is yours, with "seq")
##   rejected     game_id, snapshot
##   seat_update  game_id, seat, name, kind
##   pong         ts

const VERSION := 1
const MAX_MESSAGE := 16 * 1024
const NAME_MAX := 16
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O or 1/I
const CODE_LENGTH := 5


static func encode(t: String, payload := {}) -> String:
	var d := payload.duplicate()
	d.t = t
	return JSON.stringify(d)


## Returns the message as a Dictionary with a String "t", or {} if it isn't one.
static func decode(text: String) -> Dictionary:
	if text.length() > MAX_MESSAGE:
		return {}
	var d = JSON.parse_string(text)
	if not d is Dictionary or not d.get("t") is String:
		return {}
	return d


## Trims a player or room name to something safe to show: printable, 1–16 characters.
static func clean_name(raw, fallback := "Player") -> String:
	var s := str(raw) if raw != null else ""
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges().left(NAME_MAX)
	return out if out != "" else fallback


static func clean_code(raw) -> String:
	return str(raw).strip_edges().to_upper().left(CODE_LENGTH) if raw != null else ""
