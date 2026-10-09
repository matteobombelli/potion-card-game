class_name MediumBot
extends Bot
## Greedy: takes the move that most improves PotionEval's estimate of its potion.
## A swap also counts the damage done to the other potion, more so if that player leads.

const SWAP_MIN_GAIN := 0.05
const LEADER_HARM := 1.0
const OTHER_HARM := 0.6


func choose(view: GameState, me: int) -> Dictionary:
	var scored := score_actions(view, me, rng)
	if scored.is_empty():
		return {}
	var best: Array = scored[0]
	for s in scored:
		if s[0] > best[0]:
			best = s
	return best[1]


## [[score, action], ...] for every legal action, scored by how much it helps `me`.
## Swaps score 0 for skipping, so a swap must gain something to be worth it.
## A little seeded noise breaks ties.
static func score_actions(view: GameState, me: int, noise: RandomNumberGenerator = null) -> Array:
	var ctx := PotionEval.context(view)
	var out: Array = []
	var mine: Array = view.potions[me]
	var order: SpecialOrder = view.orders[me]
	var base := PotionEval.estimate(mine, order, ctx) if view.phase != GameState.Phase.CHOOSE_ORDER else 0.0
	var lead := _leader_other_than(view, me)
	for a in view.legal_actions(me):
		var s := 0.0
		match a.type:
			"choose_order":
				s = PotionEval.estimate([], view.order_offers[me][a.offer], ctx)
			"play_card":
				s = PotionEval.estimate(_with(mine, view.top_card(a.deck), a.side), order, ctx) - base
			"skip_swap":
				s = SWAP_MIN_GAIN
			"swap":
				var theirs: Array = view.potions[a.other_player]
				var their_order: SpecialOrder = view.orders[a.other_player]
				var my_after := mine.duplicate()
				var given: CardData = my_after.pop_at(a.own)
				var their_after := theirs.duplicate()
				var taken: CardData = their_after.pop_at(a.other)
				my_after = _with(my_after, taken, a.own_side)
				their_after = _with(their_after, given, a.other_side)
				var gain := PotionEval.estimate(my_after, order, ctx) - base
				var harm := PotionEval.estimate(theirs, their_order, ctx) - PotionEval.estimate(their_after, their_order, ctx)
				s = gain + (LEADER_HARM if a.other_player == lead else OTHER_HARM) * harm
		if noise:
			s += noise.randf_range(-0.01, 0.01)
		out.append([s, a])
	return out


static func _with(cards: Array, card: CardData, side: int) -> Array:
	var out := cards.duplicate()
	if side == GameState.Side.LEFT:
		out.push_front(card)
	else:
		out.push_back(card)
	return out


static func _leader_other_than(view: GameState, me: int) -> int:
	var best := -1
	for i in view.num_players:
		if i != me and (best < 0 or view.totals[i] > view.totals[best]):
			best = i
	return best
