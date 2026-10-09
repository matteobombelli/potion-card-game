extends Node
## Autoload "Session": settings carried from the menu into the game, saved
## preferences (user://settings.cfg) and command-line options.
##
## Command-line options (after `--`):
##   --server             run as the multiplayer server (headless)
##   --port=9080          server port      --bind=127.0.0.1  server listen address
##   --url=ws://...       server to connect to (not saved)
##   --name=Alice         player name (not saved)
##   --fast               CPU players don't pause to "think" (tests)

enum Mode { TUTORIAL, CPU, ONLINE }

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SERVER_URL := "wss://potion.matteob.dev"
const DEFAULT_PORT := 9080

# Chosen in the menu.
var mode: Mode = Mode.CPU
var num_players := 2                         # CPU mode: you plus 1–3 CPUs
var difficulty: Bot.Difficulty = Bot.Difficulty.MEDIUM
var online_start := {}                       # multiplayer: the server's game_start message

# Saved preferences.
var player_name := ""
var server_url := DEFAULT_SERVER_URL
var token := ""                              # identifies this install to the server
var tutorial_done := false

# Command line.
var server_mode := false
var port := DEFAULT_PORT
var bind_address := "*"
var fast := false


func _ready() -> void:
	_load()
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		var value := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"--server": server_mode = true
			"--port": port = int(value)
			"--bind": bind_address = value
			"--url": server_url = value
			"--name": player_name = value
			"--fast": fast = true


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "token", token)
	cfg.set_value("player", "tutorial_done", tutorial_done)
	cfg.set_value("net", "server_url", server_url)
	cfg.save(SETTINGS_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_name = cfg.get_value("player", "name", "")
		token = cfg.get_value("player", "token", "")
		tutorial_done = cfg.get_value("player", "tutorial_done", false)
		server_url = cfg.get_value("net", "server_url", DEFAULT_SERVER_URL)
	if token == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		token = "%08x%08x" % [rng.randi(), rng.randi()]
