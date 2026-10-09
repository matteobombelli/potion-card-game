class_name PotionEval
extends RefCounted
## Heuristic value of a potion that may still be growing, used by the bots.
##
## Cards only ever join at the ends, so the modifier hits already between
## existing cards are locked in. What's left open is: the outer arrows, global
## icons, the potion type and the special order. Each open bonus is counted as
## its points times a rough chance of getting the cards it needs, where the
## chance of a colour turning up is "some deck top shows it on one of your turns".

const C := CardData.CardColor
const FUTURE_CARD_VALUE := 0.5   # rough worth of a card you haven't taken yet
const TYPE_WEIGHT := 0.85
const EDGE_WEIGHT := 0.6

static var _full_deck: Array[CardData] = []


## What a player can infer about the cards still to come, from `view` alone.
## { avail: [P(colour c shows up on a turn) per colour], avail_mod, slots_left }.
static func context(view: GameState) -> Dictionary:
	if _full_deck.is_empty():
		_full_deck = DeckBuilder.build_full_deck()
	var seen := {}
	for id in view.discard:
		seen[id] = true
	for p in view.potions:
		for c in p:
			seen[c.id] = true
	var top_counts := [0, 0, 0, 0, 0]
	var top_mods := 0
	var tops := 0
	for d in view.middle_decks.size():
		var t := view.top_card(d)
		if t:
			seen[t.id] = true
			top_counts[t.color] += 1
			top_mods += 1 if t.has_modifier() else 0
			tops += 1
	var counts := [0, 0, 0, 0, 0]
	var mods := 0
	var unseen := 0
	for c in _full_deck:
		if not seen.has(c.id):
			counts[c.color] += 1
			mods += 1 if c.has_modifier() else 0
			unseen += 1
	var decks := maxi(1, tops)
	var avail: Array[float] = []
	for col in 5:
		var f := 0.5 * (float(counts[col]) / maxf(1.0, unseen)) + 0.5 * (float(top_counts[col]) / maxf(1.0, tops))
		avail.append(1.0 - pow(1.0 - f, decks))
	var fm := 0.5 * (float(mods) / maxf(1.0, unseen)) + 0.5 * (float(top_mods) / maxf(1.0, tops))
	return { "avail": avail, "avail_mod": 1.0 - pow(1.0 - fm, decks) }


## Expected final score of `cards` (with `order`, may be null) given `ctx`.
static func estimate(cards: Array, order: SpecialOrder, ctx: Dictionary) -> float:
	if order and order.is_hidden():
		order = null
	var k := cards.size()
	var slots := Rules.POTION_SIZE - k
	if slots <= 0:
		return float(Scoring.score_potion(cards, order).total)
	var avail: Array = ctx.avail
	var hits := Scoring.modifier_hits(cards)
	var v := 0.0
	for c in cards:
		v += c.value
	v += hits.size()
	v += slots * FUTURE_CARD_VALUE

	# Open arrows on the ends, and global icons that future cards could still feed.
	if k > 0:
		var lft: CardData = cards[0]
		var rgt: CardData = cards[k - 1]
		if lft.modifier == CardData.Modifier.LEFT:
			v += EDGE_WEIGHT * p_need(avail[lft.modifier_color], 1, slots)
		if rgt.modifier == CardData.Modifier.RIGHT:
			v += EDGE_WEIGHT * p_need(avail[rgt.modifier_color], 1, slots)
	for c in cards:
		if c.modifier == CardData.Modifier.GLOBAL:
			v += slots * avail[c.modifier_color] * 0.5

	v += TYPE_WEIGHT * _type_value(cards, slots, avail)
	if order:
		v += order.points * order_chance(cards, order, slots, ctx, hits)
	return v


## P(at least m successes in `slots` tries of chance p).
static func p_need(p: float, m: int, slots: int) -> float:
	if m <= 0:
		return 1.0
	if m > slots:
		return 0.0
	var total := 0.0
	for i in range(m, slots + 1):
		total += _binom(slots, i) * pow(p, i) * pow(1.0 - p, slots - i)
	return total


static func _binom(n: int, r: int) -> float:
	var out := 1.0
	for i in r:
		out = out * (n - i) / (i + 1)
	return out


static func _counts(cards: Array) -> Dictionary:
	var counts := {}
	for c in cards:
		counts[c.color] = counts.get(c.color, 0) + 1
	return counts


## Best of (points x chance) over the potion types still reachable.
static func _type_value(cards: Array, slots: int, avail: Array) -> float:
	var k := cards.size()
	if k == 0:
		return 1.0
	var counts := _counts(cards)
	var blacks: int = counts.get(C.BLACK, 0)
	var best := 0.0

	if counts.size() == 1:
		var col: int = counts.keys()[0]
		best = maxf(best, Rules.COMBOS["Samsies"] * p_need(avail[col], slots, slots))
	var need_black := maxi(0, Rules.OOPS_MIN_BLACK - blacks)
	best = maxf(best, Rules.COMBOS["Oops"] * p_need(avail[C.BLACK], need_black, slots))

	# Rainbow: the potion so far must be a run of RAINBOW_ORDER; the rest go on the ends.
	var seq: Array = cards.map(func(c): return c.color)
	var order := Rules.RAINBOW_ORDER
	for a in order.size() - k + 1:
		if order.slice(a, a + k) == seq:
			var pr := 1.0
			for i in order.size():
				if i < a or i >= a + k:
					pr *= avail[order[i]]
			best = maxf(best, Rules.COMBOS["Rainbow"] * pr)

	var top_count: int = counts.values().max()
	if top_count <= 3 and counts.size() <= 2:
		for col in counts:
			var need: int = 3 - counts[col]
			if need <= slots:
				best = maxf(best, Rules.COMBOS["Black Sheep"] * p_need(avail[col], need, slots))

	if top_count <= 2 and counts.size() <= 2:
		var pr := 1.0
		var needed := 0
		for col in counts:
			needed += 2 - counts[col]
			pr *= p_need(avail[col], 2 - counts[col], slots)
		if counts.size() == 1:
			pr *= 0.35   # plus a pair of some other colour
			needed += 2
		if needed <= slots:
			best = maxf(best, Rules.COMBOS["Twin"] * pr)

	if top_count == 1:
		var missing: Array = []
		for col in 5:
			if not counts.has(col):
				missing.append(avail[col])
		missing.sort()
		missing.reverse()
		var pr := 1.0
		for i in slots:
			pr *= missing[i]
		best = maxf(best, Rules.COMBOS["Calico"] * pr)
	return best


## Rough chance the potion ends up meeting `order`.
static func order_chance(cards: Array, order: SpecialOrder, slots: int, ctx: Dictionary, hits: Array) -> float:
	var avail: Array = ctx.avail
	var k := cards.size()
	match order.kind:
		SpecialOrder.Kind.OUTSIDE_COLOR:
			if k > 0 and (cards[0].color == order.color or cards[k - 1].color == order.color):
				return 0.9
			return p_need(avail[order.color], 1, slots)
		SpecialOrder.Kind.LACKS_COLOR:
			if cards.any(func(c): return c.color == order.color):
				return 0.0
			return pow(0.95, slots)
		SpecialOrder.Kind.ALL_MODIFIERS:
			if cards.any(func(c): return not c.has_modifier()):
				return 0.0
			return pow(ctx.avail_mod, slots)
		SpecialOrder.Kind.NO_MODIFIER_BONUS:
			if not hits.is_empty():
				return 0.0
			var open: bool = cards.any(func(c): return c.modifier == CardData.Modifier.GLOBAL) \
				or (k > 0 and (cards[0].modifier == CardData.Modifier.LEFT or cards[k - 1].modifier == CardData.Modifier.RIGHT))
			return pow(0.85, slots) * (0.7 if open else 1.0)
		SpecialOrder.Kind.OOPS_TWIN:
			var counts := _counts(cards)
			var blacks: int = counts.get(C.BLACK, 0)
			counts.erase(C.BLACK)
			if blacks > 2 or counts.size() > 1 or counts.values().any(func(n): return n > 2):
				return 0.0
			var pr := p_need(avail[C.BLACK], 2 - blacks, slots)
			if counts.is_empty():
				pr *= 0.4
			else:
				pr *= p_need(avail[counts.keys()[0]], 2 - counts.values()[0], slots)
			return pr if (2 - blacks) + (2 if counts.is_empty() else 2 - counts.values()[0]) <= slots else 0.0
		SpecialOrder.Kind.BASE_ZERO:
			var s := 0
			for c in cards:
				s += c.value
			if -s < -2 * slots or -s > slots:
				return 0.0
			return 0.5 / (1.0 + absf(s))
	return 0.0
