class_name EasyBot
extends Bot
## Mostly random: sometimes plays Medium's move, often picks a sensible side,
## and swaps at random half the time.

const SMART_CHANCE := 0.25
const GOOD_SIDE_CHANCE := 0.5
const SWAP_CHANCE := 0.5


func choose(view: GameState, me: int) -> Dictionary:
	var acts := view.legal_actions(me)
	if acts.is_empty():
		return {}
	match view.phase:
		GameState.Phase.PLAY:
			if rng.randf() < SMART_CHANCE:
				return _best(MediumBot.score_actions(view, me, rng))
			var decks := {}
			for a in acts:
				decks[a.deck] = true
			var deck: int = decks.keys()[rng.randi_range(0, decks.size() - 1)]
			var options := MediumBot.score_actions(view, me, rng).filter(func(s): return s[1].deck == deck)
			if rng.randf() < GOOD_SIDE_CHANCE:
				return _best(options)
			return options[rng.randi_range(0, options.size() - 1)][1]
		GameState.Phase.SWAP:
			var swaps := acts.filter(func(a): return a.type == "swap")
			if swaps.is_empty() or rng.randf() >= SWAP_CHANCE:
				return acts.filter(func(a): return a.type == "skip_swap")[0]
			return swaps[rng.randi_range(0, swaps.size() - 1)]
	return acts[rng.randi_range(0, acts.size() - 1)]


static func _best(scored: Array) -> Dictionary:
	var best: Array = scored[0]
	for s in scored:
		if s[0] > best[0]:
			best = s
	return best[1]
