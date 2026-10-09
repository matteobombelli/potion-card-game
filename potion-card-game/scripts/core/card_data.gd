class_name CardData
extends RefCounted
## A single card. Pure data, no nodes. `id` is unique and stable for a given
## Rules deck recipe, so cards can be referenced by id over the network.

enum CardColor { RED, GREEN, BLUE, YELLOW, BLACK }
enum Modifier { NONE, LEFT, RIGHT, GLOBAL }

const COLOR_NAMES := ["Red", "Green", "Blue", "Yellow", "Black"]

var id: int
var color: CardColor
var value: int
var modifier: Modifier = Modifier.NONE
var modifier_color: CardColor = CardColor.BLACK


static func make(p_id: int, p_color: CardColor, p_value: int, p_modifier := Modifier.NONE, p_modifier_color := CardColor.BLACK) -> CardData:
	var c := CardData.new()
	c.id = p_id
	c.color = p_color
	c.value = p_value
	c.modifier = p_modifier
	c.modifier_color = p_modifier_color
	return c


static func color_name(c: int) -> String:
	return COLOR_NAMES[c] if c >= 0 and c < COLOR_NAMES.size() else ""


func is_black() -> bool:
	return color == CardColor.BLACK


func has_modifier() -> bool:
	return modifier != Modifier.NONE


## JSON-safe form: [id, color, value, modifier, modifier_color].
func to_array() -> Array:
	return [id, color, value, modifier, modifier_color]


static func from_array(a) -> CardData:
	if a == null:
		return null
	return make(int(a[0]), int(a[1]), int(a[2]), int(a[3]), int(a[4]))


## Parses a compact spec like "R1", "Y1<R", "K-2*R" or "B0*B": colour letter (K = black),
## value, then optionally a modifier (< left, > right, * global) and its icon colour.
## Returns null if the spec is malformed. The id is -1; DeckBuilder matches it to a real card.
static func parse_spec(spec: String) -> CardData:
	var re := RegEx.create_from_string("^([RGBYK])(-?\\d)(?:([<>*])([RGBYK]))?$")
	var m := re.search(spec)
	if m == null:
		return null
	var letters := "RGBYK"
	var mod := Modifier.NONE
	var mod_color := CardColor.BLACK
	if m.get_string(3) != "":
		mod = { "<": Modifier.LEFT, ">": Modifier.RIGHT, "*": Modifier.GLOBAL }[m.get_string(3)]
		mod_color = letters.find(m.get_string(4))
	return make(-1, letters.find(m.get_string(1)), int(m.get_string(2)), mod, mod_color)


## True if this card has the same face as `o` (ids may differ).
func same_face(o: CardData) -> bool:
	return color == o.color and value == o.value and modifier == o.modifier \
		and (modifier == Modifier.NONE or modifier_color == o.modifier_color)


func _to_string() -> String:
	var s := "%s %+d" % [COLOR_NAMES[color], value]
	if has_modifier():
		s += " [%s %s]" % [["", "L", "R", "G"][modifier], COLOR_NAMES[modifier_color]]
	return s
