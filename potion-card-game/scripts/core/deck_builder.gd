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
