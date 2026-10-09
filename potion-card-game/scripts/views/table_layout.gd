class_name TableLayout
extends RefCounted
## Where things sit on the 1920x1080 table. Vertical positions derive from the
## card size, so new card art at another resolution still fits.

const SIZE := Vector2(1920, 1080)
const CENTER := SIZE / 2.0
const EDGE_MARGIN := 95.0     # screen edge to the outer edge of a potion row's cards
const SIDE_OFFSET := 460.0    # horizontal distance of corner seats from the centre
const DECK_GAP := 37.0        # space between middle decks (room for the count badge)


## Seat for each player, clockwise from the bottom: { "position": Vector2, "top": bool }.
## Top seats have their name plaque above the cards and hold new cards below them.
static func seats(n: int) -> Array:
	var top_y := EDGE_MARGIN + CardArt.SIZE.y / 2.0
	var bottom_y := SIZE.y - top_y
	var left := CENTER.x - SIDE_OFFSET
	var right := CENTER.x + SIDE_OFFSET
	var spots: Array
	match n:
		2: spots = [Vector2(CENTER.x, bottom_y), Vector2(CENTER.x, top_y)]
		3: spots = [Vector2(CENTER.x, bottom_y), Vector2(left, top_y), Vector2(right, top_y)]
		_: spots = [Vector2(left, bottom_y), Vector2(left, top_y), Vector2(right, top_y), Vector2(right, bottom_y)]
	return spots.map(func(p): return { "position": p, "top": p.y < CENTER.y })


## Centres of the middle decks, in a row across the middle of the table.
static func deck_positions(count: int) -> Array[Vector2]:
	var spacing := CardArt.SIZE.x + DECK_GAP
	var out: Array[Vector2] = []
	for i in count:
		out.append(CENTER + Vector2((i - (count - 1) / 2.0) * spacing, -5))
	return out
