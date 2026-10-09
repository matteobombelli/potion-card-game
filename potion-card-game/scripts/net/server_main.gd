extends Node
## Entry point of the headless multiplayer server (scenes/server.tscn):
##   godot --headless --path . -- --server --port=9080 --bind=127.0.0.1

var server := PotionServer.new()


func _ready() -> void:
	Engine.max_fps = 30
	var err := server.listen(Session.port, Session.bind_address)
	if err != OK:
		printerr("Couldn't listen on %s:%d (error %d)" % [Session.bind_address, Session.port, err])
		get_tree().quit(1)


func _process(delta: float) -> void:
	server.poll(delta)
