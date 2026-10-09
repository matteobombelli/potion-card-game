class_name Scoring
extends RefCounted
## Scores a potion and returns a step-by-step breakdown the UI can replay.

const C := CardData.CardColor


## Returns {
##   base: Array[int]                 # value of each card
##   mod_hits: Array[{src, dst, pts}] # modifier icon on card src awards pts to card dst
##   bonus: {name: String, pts: int}  # best potion type ("" if none)
##   order: {title, pts, met}         # the player's special order (empty if none)
##   total: int
## }
static func score_potion(cards: Array, order: SpecialOrder = null) -> Dictionary:
	var base: Array[int] = []
	var total := 0
	for c in cards:
		base.append(c.value)
		total += c.value

	var mod_hits := modifier_hits(cards)
	for h in mod_hits:
		total += h.pts

	var bonuses := applicable_bonuses(cards)
	var bonus := _best_of(bonuses)
	total += bonus.pts

	var order_result := {}
	if order:
		var names := bonuses.map(func(b): return b.name)
		var met := order.is_met(cards, mod_hits, names)
		order_result = { "title": order.title(), "pts": order.points, "met": met }
		if met:
			total += order.points
	return { "base": base, "mod_hits": mod_hits, "bonus": bonus, "order": order_result, "total": total }


## LHS/RHS icons reward the adjacent card if it matches the icon colour;
## a global icon rewards every matching card in the potion (itself included).
static func modifier_hits(cards: Array) -> Array:
	var hits: Array = []
	for i in cards.size():
		var c: CardData = cards[i]
		match c.modifier:
			CardData.Modifier.LEFT:
				if i > 0 and cards[i - 1].color == c.modifier_color:
					hits.append({ "src": i, "dst": i - 1, "pts": 1 })
			CardData.Modifier.RIGHT:
				if i < cards.size() - 1 and cards[i + 1].color == c.modifier_color:
					hits.append({ "src": i, "dst": i + 1, "pts": 1 })
			CardData.Modifier.GLOBAL:
				for j in cards.size():
					if cards[j].color == c.modifier_color:
						hits.append({ "src": i, "dst": j, "pts": 1 })
	return hits


## All potion types that apply, in rulebook order. Black counts as a colour.
static func applicable_bonuses(cards: Array) -> Array:
	var out: Array = []
	if cards.size() != Rules.POTION_SIZE:
		return out
	var counts := {}
	var seq: Array[int] = []
	for c in cards:
		counts[c.color] = counts.get(c.color, 0) + 1
		seq.append(c.color)
	var black: int = counts.get(C.BLACK, 0)
	var sizes := counts.values()

	if counts.size() == 1:
		out.append(_combo("Samsies"))
	if black >= Rules.OOPS_MIN_BLACK:
		out.append(_combo("Oops"))
	if seq == Rules.RAINBOW_ORDER:
		out.append(_combo("Rainbow"))
	if sizes.has(3):
		out.append(_combo("Black Sheep"))
	if sizes.count(2) == 2:
		out.append(_combo("Twin"))
	if counts.size() == 4:
		out.append(_combo("Calico"))
	return out


## Highest-scoring potion type; ties go to the earlier one in the rulebook.
static func best_bonus(cards: Array) -> Dictionary:
	return _best_of(applicable_bonuses(cards))


static func _combo(name: String) -> Dictionary:
	return { "name": name, "pts": Rules.COMBOS[name] }


static func _best_of(bonuses: Array) -> Dictionary:
	var best := { "name": "", "pts": 0 }
	for b in bonuses:
		if b.pts > best.pts:
			best = b
	return best
