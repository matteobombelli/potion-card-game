class_name Bot
extends RefCounted
## A computer player. Pure data, no nodes, so the server can run bots too.
##
## Bots are always handed a view built from a redacted snapshot
## (GameState.from_snapshot(gs.to_snapshot(seat))), so they only know what a
## human in that seat would: deck tops, every potion, their own order.
##
## Thinking can be spread over frames: start(), then step(budget) until it
## returns true, then result(). decide() does it all at once.

enum Difficulty { EASY, MEDIUM, OPTIMAL }

const NAMES := ["Easy", "Medium", "Optimal"]

var rng := RandomNumberGenerator.new()
var _view: GameState
var _me := 0
var _result := {}


static func create(difficulty: Difficulty, seed := -1) -> Bot:
	var b: Bot
	match difficulty:
		Difficulty.EASY: b = EasyBot.new()
		Difficulty.OPTIMAL: b = OptimalBot.new()
		_: b = MediumBot.new()
	b.set_seed(seed)
	return b


func set_seed(seed: int) -> void:
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()


func start(view: GameState, me: int) -> void:
	_view = view
	_me = me
	_result = {}


## Thinks for up to `budget_usec` microseconds; returns true once result() is ready.
func step(_budget_usec: int) -> bool:
	if _result.is_empty():
		_result = choose(_view, _me)
	return true


func result() -> Dictionary:
	return _result


func decide(view: GameState, me: int) -> Dictionary:
	start(view, me)
	while not step(1 << 30):
		pass
	return result()


## Simple bots override this; the result must be one of view.legal_actions(me).
func choose(view: GameState, me: int) -> Dictionary:
	var acts := view.legal_actions(me)
	return acts[rng.randi_range(0, acts.size() - 1)] if not acts.is_empty() else {}
