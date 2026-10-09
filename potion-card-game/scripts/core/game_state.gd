class_name GameState
extends RefCounted
## Authoritative rules engine. Pure data, no nodes, so it can run on a server.
##
## Every player action takes the acting player and returns false if it is illegal
## (wrong phase, not their turn, bad index). `apply()` accepts the same actions as
## plain dictionaries, which is the shape to send over the network.
## All randomness comes from one seeded RNG, so a game replays identically from its seed.

enum Phase { CHOOSE_ORDER, PLAY, SWAP, ROUND_OVER, GAME_OVER }
enum Side { LEFT, RIGHT }

var num_players: int
var potions: Array = []          # per player: Array[CardData], left -> right
var totals: Array[int] = []
var middle_decks: Array = []     # Array[Array[CardData]]; the last element is the face-up top
var round_index := 0             # 0-based
var first_player := 0
var current_player := 0
var phase: Phase = Phase.CHOOSE_ORDER
var last_round_scores: Array = []  # Scoring.score_potion breakdowns, filled when a round ends

# Special orders: each round every player is offered some and keeps one.
# Kept orders leave the deck for good; the rejected ones go back.
var order_deck: Array[SpecialOrder] = []
var order_offers: Array = []     # per player: Array[SpecialOrder] offered this round
var orders: Array = []           # per player: the SpecialOrder kept this round (or null)

var _turns_taken := 0
var _rng := RandomNumberGenerator.new()


func _init(p_num_players: int, seed := -1) -> void:
	num_players = p_num_players
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.randomize()
	middle_decks = DeckBuilder.deal_middle_decks(num_players + Rules.EXTRA_MIDDLE_DECKS, _rng)
	order_deck = SpecialOrder.build_deck()
	for i in num_players:
		potions.append([])
		totals.append(0)
		order_offers.append([])
		orders.append(null)
	_start_round()


# --- Queries ----------------------------------------------------------------

func top_card(deck_idx: int) -> CardData:
	var d: Array = middle_decks[deck_idx]
	return d.back() if not d.is_empty() else null


func can_play(player: int, deck_idx: int) -> bool:
	return phase == Phase.PLAY and player == current_player \
		and deck_idx >= 0 and deck_idx < middle_decks.size() \
		and not middle_decks[deck_idx].is_empty() \
		and potions[player].size() < Rules.POTION_SIZE


func is_swappable(player: int, idx: int) -> bool:
	return player >= 0 and player < num_players \
		and idx >= 0 and idx < potions[player].size() and not potions[player][idx].is_black()


## True if `player` has a colour card and some other player does too.
func swap_possible(player: int) -> bool:
	if not _has_color_card(potions[player]):
		return false
	for i in num_players:
		if i != player and _has_color_card(potions[i]):
			return true
	return false


func winners() -> Array[int]:
	var best: int = totals.max()
	var out: Array[int] = []
	for i in num_players:
		if totals[i] == best:
			out.append(i)
	return out


# --- Actions ----------------------------------------------------------------

## Network-friendly entry point, e.g. {"type": "play_card", "player": 0, "deck": 2, "side": 1}.
func apply(action: Dictionary) -> bool:
	var p: int = action.get("player", -1)
	match action.get("type", ""):
		"choose_order":
			return choose_order(p, action.get("offer", -1))
		"play_card":
			return play_card(p, action.get("deck", -1), action.get("side", -1))
		"swap":
			return swap(p, action.get("own", -1), action.get("other_player", -1),
				action.get("other", -1), action.get("other_side", -1), action.get("own_side", -1))
		"skip_swap":
			return skip_swap(p)
	return false


func choose_order(player: int, offer_idx: int) -> bool:
	if phase != Phase.CHOOSE_ORDER or player != current_player:
		return false
	var offer: Array = order_offers[player]
	if offer_idx < 0 or offer_idx >= offer.size():
		return false
	orders[player] = offer[offer_idx]
	for k in offer.size():
		if k != offer_idx:
			order_deck.append(offer[k])
	order_offers[player] = []
	_advance_order_choice()
	return true


## Takes the top card of a middle deck and puts it on one end of the player's potion.
## A black card then opens the optional swap (if any swap is possible).
func play_card(player: int, deck_idx: int, side: int) -> bool:
	if not can_play(player, deck_idx) or not _valid_side(side):
		return false
	var card: CardData = middle_decks[deck_idx].pop_back()
	_insert(potions[player], card, side)
	if card.is_black() and swap_possible(player):
		phase = Phase.SWAP
	else:
		_end_turn()
	return true


## Swaps the player's colour card at own_idx with other_player's colour card at other_idx.
## The given card lands on `other_side` of the other potion; the taken card on `own_side` of the player's.
func swap(player: int, own_idx: int, other_player: int, other_idx: int, other_side: int, own_side: int) -> bool:
	if phase != Phase.SWAP or player != current_player or other_player == player:
		return false
	if not is_swappable(player, own_idx) or not is_swappable(other_player, other_idx):
		return false
	if not _valid_side(other_side) or not _valid_side(own_side):
		return false
	var mine: Array = potions[player]
	var theirs: Array = potions[other_player]
	var given: CardData = mine.pop_at(own_idx)
	var taken: CardData = theirs.pop_at(other_idx)
	_insert(theirs, given, other_side)
	_insert(mine, taken, own_side)
	_end_turn()
	return true


func skip_swap(player: int) -> bool:
	if phase != Phase.SWAP or player != current_player:
		return false
	_end_turn()
	return true


## Host-side: discards the potions and starts the next round (or ends the game).
## Called once clients have finished showing the round's scores.
func next_round() -> bool:
	if phase != Phase.ROUND_OVER:
		return false
	for p in potions:
		p.clear()
	round_index += 1
	if round_index >= Rules.ROUNDS:
		phase = Phase.GAME_OVER
		return true
	first_player = (first_player + 1) % num_players
	_start_round()
	return true


# --- Internals --------------------------------------------------------------

func _start_round() -> void:
	_turns_taken = 0
	current_player = first_player
	_deal_orders()


## Deals offers to every player at once (late rounds may need the last orders in the deck);
## players then choose in turn order, starting with the round's first player.
func _deal_orders() -> void:
	for i in num_players:
		orders[i] = null
		var offer: Array[SpecialOrder] = []
		for k in Rules.ORDERS_OFFERED:
			if order_deck.is_empty():
				break
			offer.append(order_deck.pop_at(_rng.randi_range(0, order_deck.size() - 1)))
		order_offers[i] = offer
	phase = Phase.CHOOSE_ORDER
	current_player = first_player
	if order_offers[current_player].is_empty():
		_advance_order_choice()


## Moves to the next player who still has offers; once nobody does, drafting starts.
func _advance_order_choice() -> void:
	for step in num_players:
		if not order_offers[current_player].is_empty():
			return
		current_player = (current_player + 1) % num_players
	current_player = first_player
	phase = Phase.PLAY


func _end_turn() -> void:
	_turns_taken += 1
	if _turns_taken >= num_players * Rules.POTION_SIZE:
		_score_round()
		return
	current_player = (current_player + 1) % num_players
	phase = Phase.PLAY


func _score_round() -> void:
	last_round_scores.clear()
	for i in num_players:
		var b := Scoring.score_potion(potions[i], orders[i])
		totals[i] += b.total
		last_round_scores.append(b)
	phase = Phase.ROUND_OVER


static func _insert(potion: Array, card: CardData, side: int) -> void:
	if side == Side.LEFT:
		potion.push_front(card)
	else:
		potion.push_back(card)


static func _valid_side(side: int) -> bool:
	return side == Side.LEFT or side == Side.RIGHT


static func _has_color_card(potion: Array) -> bool:
	return potion.any(func(c): return not c.is_black())
