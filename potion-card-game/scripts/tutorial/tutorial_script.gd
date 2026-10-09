class_name TutorialScript
extends RefCounted
## The tutorial's fixed game: you (seat 0) against a scripted CPU (seat 1) with
## hand-picked deck tops and special orders. In rounds 1–2 every move is
## scripted and explained; rounds 3–4 are free play against the Easy CPU.
## tests/run_tests.gd plays the script and pins the scores the tips talk about,
## so a rules change that breaks the lesson fails a test.
##
## Card specs: colour letter (K = black), value, then optionally < > * (left,
## right, global modifier) and the icon colour. Decks are listed top first.

const SEED := 2026
const L := GameState.Side.LEFT
const R := GameState.Side.RIGHT

const DECKS := [
	["Y1", "G1", "Y1", "Y1<R", "K-2*R"],
	["K0", "R1>Y", "K-1<G", "B1", "K-1>B", "B0*B"],
	["Y0*Y", "G1", "R1", "G1", "B1", "B1"],
]
const OFFERS := [
	[["OUTSIDE:RED", "BASE_ZERO"], ["LACKS:BLUE", "ALL_MODS"]],   # round 1: you, CPU
	[["OUTSIDE:BLUE", "ALL_MODS"], ["LACKS:GREEN", "BASE_ZERO"]], # round 2
]

## The CPU's moves in rounds 1–2, in order (the bot fills in "player").
const CPU_ACTIONS := [
	{ "type": "choose_order", "offer": 0 },
	{ "type": "play_card", "deck": 1, "side": R },   # black 0
	{ "type": "play_card", "deck": 0, "side": R },   # green 1
	{ "type": "play_card", "deck": 2, "side": R },   # green 1
	{ "type": "play_card", "deck": 1, "side": R },   # black -1, arrow left at green
	{ "type": "skip_swap" },
	{ "type": "choose_order", "offer": 0 },
	{ "type": "play_card", "deck": 2, "side": R },   # red 1
	{ "type": "play_card", "deck": 1, "side": R },   # blue 1
	{ "type": "play_card", "deck": 2, "side": R },   # blue 1
	{ "type": "play_card", "deck": 1, "side": R },   # blue 0, global blue
]

## The lesson, in the order things happen. Kinds of beat:
##   step:  your move. Only `allow` can be clicked (offer index, deck index, side,
##          your card index, or [player, card index]). `pre` tips need NEXT first.
##   after: tips (with NEXT) after the CPU makes a move of this type.
##   round_end: tips after a round's scoring, before the next round starts.
## `point` aims the tip's arrow: "order:i", "deck:i", "slot:side", "card:player:i".
const BEATS := [
	# --- Round 1 ---
	{ "step": "order", "allow": 0, "point": "order:0",
		"pre": ["Welcome to POTION! Each round you brew a potion of 4 cards, drafted one at a time from the middle decks. The highest total after 4 rounds wins.",
			"First, special orders: secret bonus goals for the round. You're offered two and keep one."],
		"tip": "Red on an end is easy to get: take it for +2. (+5 for adding up to exactly 0 is tempting, but hard!)" },
	{ "step": "pick", "allow": 0, "point": "deck:0",
		"tip": "On your turn, take the top card of any middle deck. Take this yellow +1." },
	{ "step": "place", "allow": L, "point": "slot:0",
		"tip": "Your first card starts your potion. Click the slot to place it." },
	{ "after": "play_card",
		"tips": ["The CPU took a black card. Black cards are worth 0 or less, but they're useful: two of them make an OOPS potion, and taking one lets you swap cards. More on that soon."] },
	{ "step": "pick", "allow": 2, "point": "deck:2",
		"tip": "See the icon on this yellow 0? It's a global modifier: +1 for every yellow card in your potion, itself included. Take it." },
	{ "step": "place", "allow": R, "point": "slot:1",
		"tip": "New cards always go on the left or right end. Put this one on the right." },
	{ "step": "pick", "allow": 1, "point": "deck:1",
		"tip": "This red card's arrow points right: +1 if the card on its right is yellow. It's also red, for your order." },
	{ "step": "place", "allow": L, "point": "slot:0",
		"tip": "Put it on the LEFT end: the arrow points at your yellow card, and red sits on an end." },
	{ "step": "pick", "allow": 0, "point": "deck:0",
		"tip": "Three cards of one colour make a BLACK SHEEP potion (+2). Take another yellow." },
	{ "step": "place", "allow": R, "point": "slot:1",
		"tip": "Add it on the right. Your potion is complete!" },
	{ "after": "skip_swap",
		"tips": ["The CPU took another black card. Whoever takes a black card may swap one of their colour cards for someone else's. The CPU chose not to."] },
	{ "round_end": 0,
		"tips": ["Round 2! The first player moves one seat each round, so the CPU goes first. You'll learn to swap this round."] },
	# --- Round 2 ---
	{ "step": "order", "allow": 0, "point": "order:0",
		"tip": "Take 'Blue on an end' this time." },
	{ "step": "pick", "allow": 0, "point": "deck:0",
		"tip": "This yellow card's arrow points LEFT: it wants a red card on its left. Take it." },
	{ "step": "place", "allow": L, "point": "slot:0",
		"tip": "Place it." },
	{ "step": "pick", "allow": 2, "point": "deck:2",
		"tip": "You want red next to that arrow, but the CPU has the red card! Take this green card. You'll trade it soon." },
	{ "step": "place", "allow": L, "point": "slot:0",
		"tip": "Put it on the left for now." },
	{ "step": "pick", "allow": 1, "point": "deck:1",
		"tip": "Now take the black card: taking a black card lets you swap." },
	{ "step": "place", "allow": R, "point": "slot:1",
		"tip": "Its arrow points right, at blue. Put it on the right end." },
	{ "step": "swap_own", "allow": 0, "point": "card:0:0",
		"tip": "SWAP! First pick one of your colour cards to give away: the green one." },
	{ "step": "swap_other", "allow": [1, 0], "point": "card:1:0",
		"tip": "Now pick the card you take: the CPU's red card." },
	{ "step": "swap_place_other", "allow": L, "point": "slot:0",
		"tip": "You choose where your green card lands in the CPU's potion: the left end." },
	{ "step": "swap_place_own", "allow": L, "point": "slot:0",
		"tip": "The card you take lands on an end too. Put the red card on the LEFT, next to your yellow arrow." },
	{ "step": "pick", "allow": 2, "point": "deck:2",
		"tip": "Last card: blue on an end meets your order, and your black arrow points at it." },
	{ "step": "place", "allow": R, "point": "slot:1",
		"tip": "Put it on the right end." },
	{ "round_end": 1,
		"tips": ["That's the whole game! Play the last two rounds on your own against the CPU. Plan around your special order, and keep an eye on the CPU's potion."] },
]

## Tips shown while a round is scored: [round][player][stage]. A mod_hit tip
## is shown once, at the first modifier hit. {running}, {total}, {pts} and
## {name} are filled in from the live score breakdown.
const SCORE_NOTES := [
	{
		0: {
			"values": "Scoring! First your card values: {running} so far.",
			"mod_hit": "Then modifiers. Your red arrow points at a yellow card: +1. Your yellow star scores +1 for each of your 3 yellow cards.",
			"bonus": "Three yellows: {name} +{pts}. Only your best potion type counts.",
			"order": "Red on an end: your special order scores +{pts}.",
			"total": "That's {total} points this round!",
		},
		1: {
			"bonus": "The CPU's two black cards make an OOPS potion (+4). It's also a TWIN (two pairs, +2), but only the best type counts.",
			"order": "Special orders are secret until scoring. The CPU's was 'No blue': met, +2.",
		},
	},
	{
		0: {
			"mod_hit": "Your yellow arrow hits the red card, and your black arrow hits the blue card.",
			"bonus": "Red, yellow, black, blue: four different colours make a {name} potion (+{pts}). Black counts as a colour!",
			"order": "Blue on an end: +{pts}.",
			"total": "{total} points this round.",
		},
		1: {
			"order": "The CPU's secret order was 'No green'. The green card you gave it ruined it!",
		},
	},
]

## Scores the tips above rely on: [round] = [you, CPU].
const EXPECTED_SCORES := [[11, 8], [8, 8]]


static func setup() -> Dictionary:
	return { "first_player": 0, "decks": DECKS, "offers": OFFERS }


static func cpu_actions() -> Array:
	return CPU_ACTIONS


## Your moves in rounds 1–2 as apply() actions (for the tests), built from BEATS.
static func player_actions() -> Array:
	var out: Array = []
	var pick := -1
	var swap := {}
	for b in BEATS:
		match b.get("step", ""):
			"order": out.append({ "type": "choose_order", "player": 0, "offer": b.allow })
			"pick": pick = b.allow
			"place": out.append({ "type": "play_card", "player": 0, "deck": pick, "side": b.allow })
			"swap_own": swap = { "type": "swap", "player": 0, "own": b.allow }
			"swap_other":
				swap.other_player = b.allow[0]
				swap.other = b.allow[1]
			"swap_place_other": swap.other_side = b.allow
			"swap_place_own":
				swap.own_side = b.allow
				out.append(swap)
	return out
