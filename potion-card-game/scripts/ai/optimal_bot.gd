class_name OptimalBot
extends Bot
## The strongest bot: determinized Monte Carlo lookahead.
##
## For each candidate move it imagines possible worlds (unknown cards and secret
## orders filled in by WorldSampler), plays the move, then plays the rest of the
## round with Medium-style moves for everyone. Every candidate faces the same
## worlds, so luck cancels out. The score is the game margin (my total minus the
## best opponent's), so it also likes hurting the leader. Weak candidates are
## dropped as evidence comes in (successive halving).
##
## Work is done in step() slices so the game keeps animating while it thinks.

const ROLLOUT_RANDOMNESS := 0.1
const MAX_SWAP_ARMS := 8
const FIRST_CUT := 8

var max_worlds := 400        # cap on sampled worlds per decision
var max_usec := 1_000_000    # wall-clock cap per decision; 0 = none (tests use max_worlds only)

var _arms: Array = []        # [{ action, sum, n }]
var _worlds := 0
var _next_cut := FIRST_CUT
var _started_usec := 0


func start(view: GameState, me: int) -> void:
	super.start(view, me)
	_arms = []
	_worlds = 0
	_next_cut = FIRST_CUT
	_started_usec = Time.get_ticks_usec()
	var candidates: Array = []
	if view.phase == GameState.Phase.SWAP:
		var scored := MediumBot.score_actions(view, me)
		scored.sort_custom(func(a, b): return a[0] > b[0])
		candidates = scored.slice(0, MAX_SWAP_ARMS).map(func(s): return s[1])
		if not candidates.any(func(a): return a.type == "skip_swap"):
			candidates.append({ "type": "skip_swap", "player": me })
	else:
		candidates = view.legal_actions(me)
	for a in candidates:
		_arms.append({ "action": a, "sum": 0.0, "n": 0 })
	if _arms.size() <= 1:
		_result = _arms[0].action if not _arms.is_empty() else {}


func step(budget_usec: int) -> bool:
	if not _result.is_empty() or _arms.is_empty():
		return true
	var slice_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - slice_start < budget_usec:
		if _done():
			_result = _best_arm().action
			return true
		var world := WorldSampler.sample(_view, _me, rng)
		var roll_seed := rng.randi()
		for arm in _arms:
			var w := world.clone()
			if not w.apply(arm.action):
				arm.sum -= 1000.0   # shouldn't happen: the action was legal in the view
				arm.n += 1
				continue
			var r := RandomNumberGenerator.new()
			r.seed = roll_seed
			_rollout(w, r)
			arm.sum += _utility(w)
			arm.n += 1
		_worlds += 1
		if _worlds >= _next_cut and _arms.size() > 2:
			_arms.sort_custom(func(a, b): return a.sum / a.n > b.sum / b.n)
			_arms = _arms.slice(0, ceili(_arms.size() / 2.0))
			_next_cut *= 2
	return false


func _done() -> bool:
	if _worlds >= max_worlds:
		return true
	return max_usec > 0 and Time.get_ticks_usec() - _started_usec >= max_usec and _worlds > 0


func _best_arm() -> Dictionary:
	var best: Dictionary = _arms[0]
	for a in _arms:
		if a.n > 0 and (best.n == 0 or a.sum / a.n > best.sum / best.n):
			best = a
	return best


## Plays the world to the end of the round with greedy moves (and a little randomness).
static func _rollout(w: GameState, r: RandomNumberGenerator) -> void:
	while w.phase != GameState.Phase.ROUND_OVER and w.phase != GameState.Phase.GAME_OVER:
		var p := w.current_player
		if w.phase == GameState.Phase.CHOOSE_ORDER:
			p = w.players_needing_order()[0]
		if not w.apply(_policy(w, p, r)):
			return


static func _policy(w: GameState, p: int, r: RandomNumberGenerator) -> Dictionary:
	if r.randf() < ROLLOUT_RANDOMNESS:
		var acts := w.legal_actions(p)
		return acts[r.randi_range(0, acts.size() - 1)]
	var scored := MediumBot.score_actions(w, p)
	var best: Array = scored[0]
	for s in scored:
		if s[0] > best[0]:
			best = s
	return best[1]


func _utility(w: GameState) -> float:
	var best_other := -INF
	for i in w.num_players:
		if i != _me:
			best_other = maxf(best_other, w.totals[i])
	return w.totals[_me] - best_other
