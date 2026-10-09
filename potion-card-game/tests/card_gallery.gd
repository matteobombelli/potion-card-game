extends Node2D
## Every card in the deck, laid out in a grid. Handy for checking card art.
## Run it from the editor (F6 with this scene open), or capture it to a PNG:
##   godot --path . --scene res://tests/card_gallery.tscn -- <output.png>

const COLUMNS := 16
const CARD_SCALE := 0.75


func _ready() -> void:
	add_child(TableBackground.new())
	var deck := DeckBuilder.build_full_deck()
	var cell := CardArt.SIZE * CARD_SCALE + Vector2(12, 14)
	var rows := ceili(deck.size() / float(COLUMNS))
	var origin := TableLayout.CENTER - Vector2(COLUMNS - 1, rows - 1) * cell / 2.0
	for i in deck.size():
		var v := CardView.new(deck[i])
		v.scale = Vector2.ONE * CARD_SCALE
		v.position = origin + Vector2(i % COLUMNS, floorf(i / float(COLUMNS))) * cell
		add_child(v)

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(args[0])
		get_tree().quit()
