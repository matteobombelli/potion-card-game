extends SceneTree
## Bot tests (slower than the rules tests):
##   godot --headless --path . -s res://tests/bot_tests.gd [quick]
## Bots must always return a legal move from a redacted view, and stronger
## difficulties must beat weaker ones over seeded games.

const D := Bot.Difficulty

var _fails := 0
var _passes := 0
var _quick := false
var _think_usec := {}   # difficulty -> [total usec, decisions]


func _init() -> void:
	_quick = OS.get_cmdline_user_args().has("quick")
	test_legal_moves()
	test_strength()
	for d in _think_usec:
		var t: Array = _think_usec[d]
		print("%s: %.1f ms per decision (%d decisions)" % [Bot.NAMES[d], t[0] / 1000.0 / maxi(1, t[1]), t[1]])
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func make_bot(d: int, seed: int) -> Bot:
	var b := Bot.create(d, seed)
	if b is OptimalBot:
		b.max_worlds = 16 if _quick else 32
		b.max_usec = 0
	return b


## Plays a game where seat i is played by bots[i]; every decision comes from a
## redacted view. Returns the final GameState.
func play(gs: GameState, bots: Array) -> GameState:
	while gs.phase != GameState.Phase.GAME_OVER:
		if gs.phase == GameState.Phase.ROUND_OVER:
			gs.next_round()
			continue
		var p := gs.current_player
		if gs.phase == GameState.Phase.CHOOSE_ORDER:
			p = gs.players_needing_order()[0]
		var view := GameState.from_snapshot(JSON.parse_string(JSON.stringify(gs.to_snapshot(p))))
		var bot: Bot = bots[p]
		var t := Time.get_ticks_usec()
		var a := bot.decide(view, p)
		var key := D.OPTIMAL if bot is OptimalBot else (D.MEDIUM if bot is MediumBot else D.EASY)
		var acc: Array = _think_usec.get(key, [0, 0])
		_think_usec[key] = [acc[0] + Time.get_ticks_usec() - t, acc[1] + 1]
		var legal := gs.legal_actions(p).has(a)
		check(legal, "%s returned a legal action: %s" % [bot.get_script().get_global_name(), a])
		if not legal:
			return gs
		gs.apply(a)
	return gs


func test_legal_moves() -> void:
	var games := 3 if _quick else 10
	for n in [2, 3, 4]:
		for g in games:
			var bots: Array = []
			for i in n:
				bots.append(make_bot([D.EASY, D.MEDIUM, D.OPTIMAL][(i + g) % 3] if n > 2 or g % 2 == 0 else D.EASY, g * 10 + i))
			var gs := play(GameState.new(n, 1000 + g * 7 + n), bots)
			check(gs.phase == GameState.Phase.GAME_OVER, "bot game finishes (n=%d)" % n)


## Head-to-head 2-player games, swapping seats each game. Returns the win share of `a`.
func head_to_head(a: int, b: int, games: int) -> float:
	var wins := 0.0
	for g in games:
		var seats := [make_bot(a, g * 2), make_bot(b, g * 2 + 1)]
		var a_seat := 0
		if g % 2 == 1:
			seats.reverse()
			a_seat = 1
		var gs := play(GameState.new(2, 5000 + g), seats)
		var w := gs.winners()
		if w.has(a_seat):
			wins += 1.0 / w.size()
	return wins / games


func test_strength() -> void:
	var games := 20 if _quick else 40
	var me := head_to_head(D.MEDIUM, D.EASY, games)
	print("Medium vs Easy: %.0f%%" % (me * 100))
	check(me > 0.6, "Medium beats Easy (%.0f%%)" % (me * 100))
	var oe := head_to_head(D.OPTIMAL, D.EASY, games / 2)
	print("Optimal vs Easy: %.0f%%" % (oe * 100))
	check(oe > 0.7, "Optimal beats Easy (%.0f%%)" % (oe * 100))
	var om := head_to_head(D.OPTIMAL, D.MEDIUM, games / 2)
	print("Optimal vs Medium: %.0f%%" % (om * 100))
	check(om > 0.5, "Optimal beats Medium (%.0f%%)" % (om * 100))
