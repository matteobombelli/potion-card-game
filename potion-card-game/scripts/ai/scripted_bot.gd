class_name ScriptedBot
extends Bot
## Plays a fixed list of moves (the tutorial's CPU), then hands over to another bot.
## Each scripted move is used only when it is legal right now, so a script that
## falls out of step can't break the game; the fallback bot plays instead.

var script_actions: Array = []   # apply() dictionaries, in the order they will be played
var fallback: Bot


func _init(actions: Array = [], p_fallback: Bot = null) -> void:
	script_actions = actions.duplicate(true)
	fallback = p_fallback if p_fallback else EasyBot.new()


func start(view: GameState, me: int) -> void:
	super.start(view, me)
	if not script_actions.is_empty():
		var a: Dictionary = script_actions[0].duplicate()
		a.player = me
		if view.clone().apply(a):
			script_actions.pop_front()
			_result = a
			return
	fallback.start(view, me)


func step(budget_usec: int) -> bool:
	if not _result.is_empty():
		return true
	if fallback.step(budget_usec):
		_result = fallback.result()
		return true
	return false
