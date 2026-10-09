class_name LocalMatch
extends Match
## A game on this machine: the real GameState plus a bot for every other seat
## (VS CPU and the tutorial). Bots decide from the same redacted view a player
## in their seat would get, after a short "thinking" pause.

const THINK_MIN := 0.6
const THINK_MAX := 1.2
const STEP_USEC := 4000   # thinking time per frame for slow bots

var gs: GameState
var bots := {}            # seat -> Bot
var hold_bots := false    # the tutorial pauses the CPU while a tip is up
var _thinking := {}       # seat -> { wait: seconds left, done: bool }
var _seq := 0
var _rng := RandomNumberGenerator.new()


func _init(p_gs: GameState, p_bots: Dictionary, names: Array[String], p_local := 0) -> void:
	gs = p_gs
	bots = p_bots
	local_player = p_local
	_rng.randomize()
	seat_names = names
	for i in gs.num_players:
		seat_kinds.append("you" if i == local_player else "cpu")


func begin() -> void:
	started.emit.call_deferred(_snapshot())


func submit(action: Dictionary) -> void:
	var a := action.duplicate()
	a.player = local_player
	if gs.apply(a):
		event.emit(a, _snapshot())
	else:
		rejected.emit(_snapshot())


func scores_shown() -> void:
	if gs.phase == GameState.Phase.ROUND_OVER:
		gs.next_round()
		_thinking.clear()
		event.emit({ "type": "next_round" }, _snapshot())


func _snapshot() -> Dictionary:
	_seq += 1
	var s := gs.to_snapshot(local_player)
	s.seq = _seq
	return s


func _acting_bots() -> Array:
	var seats: Array = []
	match gs.phase:
		GameState.Phase.CHOOSE_ORDER:
			seats = Array(gs.players_needing_order())
		GameState.Phase.PLAY, GameState.Phase.SWAP:
			seats = [gs.current_player]
	return seats.filter(func(s): return bots.has(s))


func _process(delta: float) -> void:
	if hold_bots:
		return
	for seat in _acting_bots():
		var bot: Bot = bots[seat]
		if not _thinking.has(seat):
			bot.start(GameState.from_snapshot(gs.to_snapshot(seat)), seat)
			var wait := 0.02 if Session.fast else _rng.randf_range(THINK_MIN, THINK_MAX)
			_thinking[seat] = { "wait": wait, "done": false }
		var t: Dictionary = _thinking[seat]
		if not t.done:
			t.done = bot.step(STEP_USEC)
		if not client_busy:
			t.wait -= delta
		if t.done and t.wait <= 0.0 and not client_busy:
			_thinking.erase(seat)
			var a := bot.result()
			if not gs.apply(a):
				push_error("LocalMatch: bot %d made an illegal move %s" % [seat, a])
				a = gs.legal_actions(seat)[0]
				gs.apply(a)
			event.emit(GameState.redact_action(a, local_player), _snapshot())
			return   # one move per frame, so the controller sees them in order
