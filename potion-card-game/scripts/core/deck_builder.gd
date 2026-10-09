class_name DeckBuilder
extends RefCounted
## Builds the deck from the recipes in Rules and deals it into middle decks.


static func build_full_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for color in Rules.SUITS:
		_add_cards(deck, color, Rules.SUIT_CARDS)
	_add_cards(deck, CardData.CardColor.BLACK, Rules.BLACK_CARDS)
	return deck


## Returns `n` decks. Each deck's last element is its face-up top card.
## Colour cards are dealt round-robin first, then black cards, so both are split evenly.
static func deal_middle_decks(n: int, rng: RandomNumberGenerator) -> Array:
	var all := build_full_deck()
	var colors := all.filter(func(c): return not c.is_black())
	var blacks := all.filter(func(c): return c.is_black())
	shuffle(colors, rng)
	shuffle(blacks, rng)
	var decks: Array = []
	for i in n:
		decks.append([] as Array[CardData])
	var dealt := colors + blacks
	for i in dealt.size():
		decks[i % n].append(dealt[i])
	for d in decks:
		shuffle(d, rng)
	return decks


## Like deal_middle_decks, but with scripted cards on top (used by the tutorial).
## `stacks[i]` lists card specs for deck i, top first (see CardData.parse_spec). Those
## cards are taken out of the full deck; the rest are shuffled and dealt underneath so
## the decks end up the same size. Returns [] if a spec is bad or a card runs out.
static func deal_fixed(n: int, stacks: Array, rng: RandomNumberGenerator) -> Array:
	var pool := build_full_deck()
	var tops: Array = []
	for i in n:
		var top: Array[CardData] = []
		var specs: Array = stacks[i] if i < stacks.size() else []
		for spec in specs:
			var want := CardData.parse_spec(spec)
			var idx := -1 if want == null else pool.find_custom(func(c): return c.same_face(want))
			if idx < 0:
				push_error("DeckBuilder.deal_fixed: no card left for spec '%s'" % spec)
				return []
			top.append(pool.pop_at(idx))
		tops.append(top)
	shuffle(pool, rng)
	var total: int = pool.size() + tops.reduce(func(a, t): return a + t.size(), 0)
	var decks: Array = []
	for i in n:
		var target: int = total / n + (1 if i < total % n else 0)
		var d: Array[CardData] = []
		for k in maxi(0, target - tops[i].size()):
			if not pool.is_empty():
				d.append(pool.pop_back())
		var top: Array = tops[i].duplicate()
		top.reverse()   # specs are listed top first; the deck's top is its last element
		d.append_array(top)
		decks.append(d)
	for c in pool:   # only if a stack was longer than its share
		decks[0].push_front(c)
	return decks


## Fisher-Yates using the given RNG, so a seeded game is reproducible (needed for online play).
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _add_cards(deck: Array[CardData], color: int, recipes: Array) -> void:
	for r in recipes:
		var mod: int = r.get("modifier", CardData.Modifier.NONE)
		if r.has("icons"):
			for icon in r.icons:
				deck.append(CardData.make(deck.size(), color, r.value, mod, icon))
		else:
			for i in r.copies:
				deck.append(CardData.make(deck.size(), color, r.value, mod))
