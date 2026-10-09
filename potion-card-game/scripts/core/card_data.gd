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


func _to_string() -> String:
	var s := "%s %+d" % [COLOR_NAMES[color], value]
	if has_modifier():
		s += " [%s %s]" % [["", "L", "R", "G"][modifier], COLOR_NAMES[modifier_color]]
	return s
