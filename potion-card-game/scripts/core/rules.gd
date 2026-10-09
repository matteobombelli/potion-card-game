class_name Rules
extends RefCounted
## Every tunable number in the game lives here. Playtest changes should only
## need to touch this file (and the tests that pin the numbers down).

const C := CardData.CardColor
const M := CardData.Modifier
const SUITS: Array[int] = [C.RED, C.GREEN, C.BLUE, C.YELLOW]
const ALL_COLORS: Array[int] = [C.RED, C.GREEN, C.BLUE, C.YELLOW, C.BLACK]

const ROUNDS := 4
const POTION_SIZE := 4
const EXTRA_MIDDLE_DECKS := 1   # middle decks = players + this
const ORDERS_OFFERED := 2       # special orders offered to each player per round (they keep one)

# --- Deck -------------------------------------------------------------------
# Each recipe makes `copies` plain cards, or one card per colour in `icons`.

## Made once for every suit colour.
const SUIT_CARDS := [
	{ "value": 1, "copies": 5 },
	{ "value": 1, "modifier": M.LEFT, "icons": ALL_COLORS },
	{ "value": 1, "modifier": M.RIGHT, "icons": ALL_COLORS },
	{ "value": 0, "modifier": M.GLOBAL, "icons": ALL_COLORS },
]

const BLACK_CARDS := [
	{ "value": 0, "copies": 4 },
	{ "value": -1, "modifier": M.LEFT, "icons": SUITS },
	{ "value": -1, "modifier": M.RIGHT, "icons": SUITS },
	{ "value": -2, "modifier": M.GLOBAL, "icons": SUITS },
]

# --- Potion types (only the best one scores) -------------------------------

const COMBOS := {
	"Samsies": 4,      # all cards the same colour
	"Oops": 4,         # OOPS_MIN_BLACK or more black cards
	"Rainbow": 5,      # exactly RAINBOW_ORDER, left to right
	"Black Sheep": 2,  # three cards of one colour
	"Twin": 2,         # two pairs
	"Calico": 2,       # four different colours (black counts)
}
const OOPS_MIN_BLACK := 2
const RAINBOW_ORDER: Array[int] = [C.RED, C.YELLOW, C.GREEN, C.BLUE]

# --- Special orders ----------------------------------------------------------
# `per_suit` makes one order per suit colour; otherwise `copies` identical ones.

const ORDERS := [
	{ "kind": SpecialOrder.Kind.OUTSIDE_COLOR, "points": 2, "per_suit": true },
	{ "kind": SpecialOrder.Kind.LACKS_COLOR, "points": 2, "per_suit": true },
	{ "kind": SpecialOrder.Kind.ALL_MODIFIERS, "points": 2, "copies": 4 },
	{ "kind": SpecialOrder.Kind.NO_MODIFIER_BONUS, "points": 3, "copies": 4 },
	{ "kind": SpecialOrder.Kind.OOPS_TWIN, "points": 4, "copies": 2 },
	{ "kind": SpecialOrder.Kind.BASE_ZERO, "points": 5, "copies": 2 },
]
