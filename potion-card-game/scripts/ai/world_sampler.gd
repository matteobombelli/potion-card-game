class_name WorldSampler
extends RefCounted
## Turns a player's redacted view into one possible full game: the unknown cards
## under the deck tops, opponents' secret orders and offers are filled in at random
## from what that player hasn't seen. Used by OptimalBot's lookahead.

static var _full_deck: Array[CardData] = []
static var _order_deck: Array[SpecialOrder] = []


static func sample(view: GameState, me: int, rng: RandomNumberGenerator) -> GameState:
	if _full_deck.is_empty():
		_full_deck = DeckBuilder.build_full_deck()
		_order_deck = SpecialOrder.build_deck()
	var w := view.clone()
	w.reseed(rng.randi())

	var seen := {}
	for id in view.discard:
		seen[id] = true
	for p in view.potions:
		for c in p:
			seen[c.id] = true
	for d in view.middle_decks:
		for c in d:
			if c:
				seen[c.id] = true
	var pool: Array = _full_deck.filter(func(c): return not seen.has(c.id))
	DeckBuilder.shuffle(pool, rng)
	for d in w.middle_decks:
		for i in d.size():
			if d[i] == null:
				d[i] = pool.pop_back() if not pool.is_empty() else _full_deck[0]

	var known := {}
	for o in view.orders:
		if o and not o.is_hidden():
			known[o.id] = true
	for offer in view.order_offers:
		for o in offer:
			if o:
				known[o.id] = true
	for o in view.order_deck:
		if o:
			known[o.id] = true
	var orders: Array = _order_deck.filter(func(o): return not known.has(o.id))
	DeckBuilder.shuffle(orders, rng)
	var draw := func() -> SpecialOrder:
		return orders.pop_back() if not orders.is_empty() else _order_deck[rng.randi_range(0, _order_deck.size() - 1)]
	for i in w.num_players:
		if w.orders[i] and w.orders[i].is_hidden():
			w.orders[i] = draw.call()
		var offer: Array = w.order_offers[i]
		for k in offer.size():
			if offer[k] == null:
				offer[k] = draw.call()
	for k in w.order_deck.size():
		if w.order_deck[k] == null:
			w.order_deck[k] = draw.call()
	return w
