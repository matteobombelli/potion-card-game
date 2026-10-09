class_name Room
extends RefCounted
## One multiplayer room on the server: its members, settings and (while
## playing) the authoritative GameState. Everyone gets their own redacted
## snapshot after every move. A player who drops mid-game is replaced by a
## Medium CPU; after the game, everyone present can vote for a rematch.

enum State { LOBBY, PLAYING, FINISHED }

const STATE_NAMES := ["lobby", "playing", "finished"]
const BOT_THINK_MIN := 0.7
const BOT_THINK_MAX := 1.4
const SCORE_WAIT_BASE := 10.0     # seconds to wait for "scores shown" acks...
const SCORE_WAIT_PER_PLAYER := 8.0  # ...plus this much per player

var code: String
var name: String
var cap := 4
var private := false
var host_id := -1
var state: State = State.LOBBY
var members: Array = []    # [{ id, name, rematch }] in join order

var gs: GameState
var seats: Array = []      # per seat: { id (client id or -1), name, bot (Bot or null) }
var game_id := 0
var seq := 0
var _acks := {}            # seat -> true once that player has shown the round's scores
var _score_wait := 0.0
var _bot_wait := {}        # seat -> seconds left before that bot moves
var _server: PotionServer
var _rng := RandomNumberGenerator.new()


func _init(p_server: PotionServer, p_code: String, p_name: String, p_cap: int, p_private: bool) -> void:
	_server = p_server
	code = p_code
	name = p_name
	cap = clampi(p_cap, 2, 4)
	private = p_private
	_rng.randomize()


func member(id: int) -> Dictionary:
	for m in members:
		if m.id == id:
			return m
	return {}


func is_full() -> bool:
	return members.size() >= cap


func human_count() -> int:
	return members.size()


## Listing entry for the room browser. Private rooms don't show their code.
func public_info() -> Dictionary:
	var host := member(host_id)
	return { "code": null if private else code, "name": name, "private": private, "players": members.size(),
		"cap": cap, "state": STATE_NAMES[state], "host_name": host.get("name", "") }


## What members see. They always see the code, so they can invite others.
func info_for(id: int) -> Dictionary:
	return { "code": code, "name": name, "cap": cap, "private": private, "host": host_id, "state": STATE_NAMES[state],
		"you": id, "members": members.map(func(m): return { "id": m.id, "name": m.name, "rematch": m.rematch }) }


func broadcast_info() -> void:
	for m in members:
		_server.send(m.id, "room", info_for(m.id))


# --- Membership ---------------------------------------------------------------

## Adds a client; returns an error code, or "" on success.
func add_member(id: int, client_name: String) -> String:
	if state == State.PLAYING:
		return "in_game"
	if is_full():
		return "room_full"
	members.append({ "id": id, "name": _unique_name(client_name), "rematch": false })
	if host_id < 0:
		host_id = id
	broadcast_info()
	return ""


## Removes a client (left or disconnected). Mid-game, a CPU takes their seat.
func remove_member(id: int) -> void:
	var m := member(id)
	if m.is_empty():
		return
	members.erase(m)
	if host_id == id:
		host_id = members[0].id if not members.is_empty() else -1
	if state == State.PLAYING:
		for s in seats.size():
			if seats[s].id == id:
				seats[s].id = -1
				seats[s].name = "%s (CPU)" % seats[s].name
				seats[s].bot = Bot.create(Bot.Difficulty.MEDIUM)
				_acks[s] = true
				for other in members:
					_server.send(other.id, "seat_update", { "game_id": game_id, "seat": s, "name": seats[s].name, "kind": "bot" })
	if state == State.FINISHED:
		_maybe_rematch()
	broadcast_info()


func _unique_name(want: String) -> String:
	var taken := members.map(func(m): return m.name)
	if not taken.has(want):
		return want
	var k := 2
	while taken.has("%s %d" % [want.left(Protocol.NAME_MAX - 2), k]):
		k += 1
	return "%s %d" % [want.left(Protocol.NAME_MAX - 2), k]


# --- Game -----------------------------------------------------------------------

## Starts a game with everyone in the room, seated in join order, with a random first player.
func start_game() -> void:
	var n := members.size()
	gs = GameState.new(n, _rng.randi() & 0x7fffffff, { "first_player": _rng.randi_range(0, n - 1) })
	seats = members.map(func(m): return { "id": m.id, "name": m.name, "bot": null })
	game_id += 1
	seq = 0
	_acks = {}
	_bot_wait = {}
	state = State.PLAYING
	for m in members:
		m.rematch = false
	var seat_list: Array = seats.map(func(s): return { "name": s.name, "kind": "human" })
	for s in seats.size():
		_server.send(seats[s].id, "game_start", { "game_id": game_id, "you": s, "seats": seat_list, "snapshot": _snapshot(s) })
	broadcast_info()


func seat_of(id: int) -> int:
	for s in seats.size():
		if seats[s].id == id:
			return s
	return -1


func handle_action(id: int, action: Dictionary) -> void:
	if state != State.PLAYING:
		return
	var seat := seat_of(id)
	if seat < 0:
		return
	var a := action.duplicate()
	a.player = seat
	if not gs.apply(a):
		_server.send(id, "rejected", { "game_id": game_id, "snapshot": _snapshot(seat) })
		return
	_broadcast_event(a)


func handle_ack(id: int, p_game_id: int, round_index: int) -> void:
	var seat := seat_of(id)
	if state == State.PLAYING and seat >= 0 and p_game_id == game_id and round_index == gs.round_index \
			and gs.phase == GameState.Phase.ROUND_OVER:
		_acks[seat] = true


func set_rematch(id: int, ready: bool) -> void:
	var m := member(id)
	if state != State.FINISHED or m.is_empty():
		return
	m.rematch = ready
	broadcast_info()
	_maybe_rematch()


func _maybe_rematch() -> void:
	if members.size() >= 2 and members.all(func(m): return m.rematch):
		start_game()


## Runs the CPUs and the pause between rounds.
func poll(delta: float) -> void:
	if state != State.PLAYING:
		return
	if gs.phase == GameState.Phase.ROUND_OVER:
		_score_wait -= delta
		var all_acked := true
		for s in seats.size():
			if seats[s].bot == null and not _acks.has(s):
				all_acked = false
		if all_acked or _score_wait <= 0.0:
			_acks = {}
			gs.next_round()
			_broadcast_event({ "type": "next_round" })
		return
	var acting: Array = Array(gs.players_needing_order()) if gs.phase == GameState.Phase.CHOOSE_ORDER else [gs.current_player]
	for s in acting:
		var bot: Bot = seats[s].bot
		if bot == null:
			continue
		if not _bot_wait.has(s):
			_bot_wait[s] = _rng.randf_range(BOT_THINK_MIN, BOT_THINK_MAX)
		_bot_wait[s] -= delta
		if _bot_wait[s] <= 0.0:
			_bot_wait.erase(s)
			var a := bot.decide(GameState.from_snapshot(gs.to_snapshot(s)), s)
			if not gs.apply(a):
				a = gs.legal_actions(s)[0]
				gs.apply(a)
			_broadcast_event(a)
			return


func _broadcast_event(action: Dictionary) -> void:
	seq += 1
	for s in seats.size():
		if seats[s].id >= 0:
			_server.send(seats[s].id, "game_event", { "game_id": game_id, "action": GameState.redact_action(action, s), "snapshot": _snapshot(s) })
	if gs.phase == GameState.Phase.ROUND_OVER:
		_score_wait = SCORE_WAIT_BASE + SCORE_WAIT_PER_PLAYER * gs.num_players
		_acks = {}
	elif gs.phase == GameState.Phase.GAME_OVER:
		state = State.FINISHED
		broadcast_info()
		_server.mark_rooms_dirty()


func _snapshot(seat: int) -> Dictionary:
	var s := gs.to_snapshot(seat)
	s.seq = seq
	return s
