class_name SpecialOrder
extends RefCounted
## A per-round bonus goal. Each round every player is offered some and keeps one.
## The deck composition and point values live in Rules.ORDERS.

enum Kind { OUTSIDE_COLOR, LACKS_COLOR, ALL_MODIFIERS, NO_MODIFIER_BONUS, OOPS_TWIN, BASE_ZERO }

var id: int
var kind: Kind
var points: int
var color: int = -1   # CardData.CardColor for the colour orders, -1 otherwise


static func make(p_id: int, p_kind: Kind, p_points: int, p_color := -1) -> SpecialOrder:
	var o := SpecialOrder.new()
	o.id = p_id
	o.kind = p_kind
	o.points = p_points
	o.color = p_color
	return o


static func build_deck() -> Array[SpecialOrder]:
	var out: Array[SpecialOrder] = []
	for r in Rules.ORDERS:
		if r.get("per_suit", false):
			for c in Rules.SUITS:
				out.append(make(out.size(), r.kind, r.points, c))
		else:
			for i in r.copies:
				out.append(make(out.size(), r.kind, r.points))
	return out


## Stands in for another player's order that you can't see yet.
static func hidden() -> SpecialOrder:
	return make(-1, Kind.OUTSIDE_COLOR, 0)


func is_hidden() -> bool:
	return id < 0


## JSON-safe form: [id, kind, points, color].
func to_array() -> Array:
	return [id, kind, points, color]


static func from_array(a) -> SpecialOrder:
	if a == null:
		return null
	return make(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


## Parses a tutorial spec like "OUTSIDE:RED", "LACKS:BLUE", "ALL_MODS", "NO_MOD",
## "OOPS_TWIN" or "BASE_ZERO" into [kind, color], or [] if malformed.
static func parse_spec(spec: String) -> Array:
	var parts := spec.split(":")
	var kinds := { "OUTSIDE": Kind.OUTSIDE_COLOR, "LACKS": Kind.LACKS_COLOR, "ALL_MODS": Kind.ALL_MODIFIERS,
		"NO_MOD": Kind.NO_MODIFIER_BONUS, "OOPS_TWIN": Kind.OOPS_TWIN, "BASE_ZERO": Kind.BASE_ZERO }
	if not kinds.has(parts[0]):
		return []
	var color := -1
	if parts.size() > 1:
		color = CardData.COLOR_NAMES.map(func(n): return n.to_upper()).find(parts[1])
		if color < 0:
			return []
	return [kinds[parts[0]], color]


## `mod_hits` and `bonus_names` come from Scoring so nothing is computed twice.
func is_met(cards: Array, mod_hits: Array, bonus_names: Array) -> bool:
	if cards.is_empty():
		return false
	match kind:
		Kind.OUTSIDE_COLOR:
			return cards.front().color == color or cards.back().color == color
		Kind.LACKS_COLOR:
			return cards.all(func(c): return c.color != color)
		Kind.ALL_MODIFIERS:
			return cards.all(func(c): return c.modifier != CardData.Modifier.NONE)
		Kind.NO_MODIFIER_BONUS:
			return mod_hits.is_empty()
		Kind.OOPS_TWIN:
			return bonus_names.has("Oops") and bonus_names.has("Twin")
		Kind.BASE_ZERO:
			return cards.reduce(func(sum, c): return sum + c.value, 0) == 0
	return false


## Short label for the player's plaque.
func title() -> String:
	var col := CardData.color_name(color)
	match kind:
		Kind.OUTSIDE_COLOR: return "%s on an end" % col
		Kind.LACKS_COLOR: return "No %s" % col.to_lower()
		Kind.ALL_MODIFIERS: return "All modifiers"
		Kind.NO_MODIFIER_BONUS: return "No modifier pts"
		Kind.OOPS_TWIN: return "Oops + Twin"
		Kind.BASE_ZERO: return "Base value 0"
	return "?"


## Full rules text for the choice screen.
func description() -> String:
	var col := CardData.color_name(color).to_lower()
	match kind:
		Kind.OUTSIDE_COLOR: return "A %s card on the left or right end of your potion." % col
		Kind.LACKS_COLOR: return "Your potion contains no %s cards." % col
		Kind.ALL_MODIFIERS: return "Every card in your potion has a modifier."
		Kind.NO_MODIFIER_BONUS: return "Your potion scores no modifier bonuses."
		Kind.OOPS_TWIN: return "Your potion is both an Oops and a Twin potion."
		Kind.BASE_ZERO: return "Card values add up to exactly 0 (before modifiers and bonuses)."
	return ""


func _to_string() -> String:
	return "%s (+%d)" % [title(), points]
