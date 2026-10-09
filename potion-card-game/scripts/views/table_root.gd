class_name TableRoot
extends Node2D
## Shared scene scaffolding for the menu and the game: background, camera and
## draw layers, registered with Fx when the scene enters the tree.

var camera := Camera2D.new()
var board_layer := Node2D.new()   # potion rows, middle decks
var cards_layer := Node2D.new()   # loose cards that move between places
var fx_layer := Node2D.new()      # particles and floating text
var ui := CanvasLayer.new()       # screen-space text (banners)


func _init() -> void:
	add_child(TableBackground.new())
	camera.position = TableLayout.CENTER
	add_child(camera)
	add_child(board_layer)
	add_child(cards_layer)
	fx_layer.z_index = 20
	add_child(fx_layer)
	add_child(ui)


func _enter_tree() -> void:
	Fx.use_scene(fx_layer, ui, camera)
