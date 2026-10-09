extends TableRoot
## Multiplayer lobby: connect (name and server), browse every room on the server,
## create or join one (private rooms need their code), then wait in the room
## until the host starts. Net switches to the game when the server starts it.

const MAIN_MENU := "res://scenes/main_menu.tscn"
const LOCAL_URL := "ws://localhost:%d"
const WIDTH := 1150.0

var _connect_panel := VBoxContainer.new()
var _browser_panel := VBoxContainer.new()
var _room_panel := VBoxContainer.new()
var _status := UiKit.label("", 26, Palette.TEXT_DIM, true)

var _name_edit := UiKit.line_edit("", "Your name", 30, Protocol.NAME_MAX)
var _url_edit := UiKit.line_edit("", "wss://server", 24)
var _rooms_list := VBoxContainer.new()
var _code_edit := UiKit.line_edit("", "CODE", 30, Protocol.CODE_LENGTH)
var _room_name_edit := UiKit.line_edit("", "Room name", 28, Protocol.NAME_MAX)
var _new_cap := 4
var _new_private := false
var _browser_title := UiKit.label("", 40, Palette.TITLE, true)

var _room_title := UiKit.label("", 44, Palette.TITLE, true)
var _room_code := UiKit.label("", 64, Palette.SCORE, true)
var _room_info := UiKit.label("", 26, Palette.TEXT_DIM, true)
var _members_list := VBoxContainer.new()
var _host_box := VBoxContainer.new()
var _start_button := UiKit.button("START GAME", 36)
var _room_hint := UiKit.label("", 26, Palette.TEXT_DIM, true)


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 20)
	ui.add_child(root)
	var title := UiKit.label("MULTIPLAYER", 72, Palette.TITLE, true)
	root.add_child(title)
	for p in [_connect_panel, _browser_panel, _room_panel]:
		p.custom_minimum_size = Vector2(WIDTH, 0)
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		p.add_theme_constant_override("separation", 16)
		root.add_child(p)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH, 0)
	_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_status)
	_build_connect()
	_build_browser()
	_build_room()

	Net.connected.connect(_refresh)
	Net.disconnected.connect(func(reason: String):
		_set_status(reason, Palette.NEGATIVE)
		_refresh())
	Net.rooms_changed.connect(_refresh_rooms)
	Net.room_changed.connect(_refresh)
	Net.server_error.connect(func(_code: String, msg: String): _set_status(msg, Palette.NEGATIVE))
	_refresh()
	if Net.is_online():
		Net.send("list_rooms")


func _set_status(text: String, color := Palette.TEXT_DIM) -> void:
	_status.text = text
	_status.label_settings.font_color = color


func _row(children: Array, sep := 20) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", sep)
	for c in children:
		row.add_child(c)
	return row


func _button(text: String, on_press: Callable, size := 30) -> Button:
	var b := UiKit.button(text, size)
	b.pressed.connect(on_press)
	return b


# --- Connect -------------------------------------------------------------------

func _build_connect() -> void:
	_name_edit.text = Session.player_name
	_name_edit.custom_minimum_size = Vector2(520, 0)
	_url_edit.text = Session.server_url
	_url_edit.custom_minimum_size = Vector2(520, 0)
	_name_edit.text_submitted.connect(func(_t): _connect(_url_edit.text))
	_connect_panel.add_child(_row([UiKit.label("NAME", 28, Palette.TEXT_DIM), _name_edit]))
	_connect_panel.add_child(_row([UiKit.label("SERVER", 24, Palette.TEXT_DIM), _url_edit]))
	_connect_panel.add_child(_row([
		_button("BACK", func(): get_tree().change_scene_to_file(MAIN_MENU)),
		_button("HOST LOCAL SERVER", _host_local, 26),
		_button("CONNECT", func(): _connect(_url_edit.text), 36),
	]))


func _connect(url: String) -> void:
	var player := Protocol.clean_name(_name_edit.text, "")
	if player == "":
		_set_status("Pick a name first.", Palette.NEGATIVE)
		return
	Session.player_name = player
	if url != Session.server_url and not url.begins_with("ws://localhost") and not url.begins_with("ws://127.0.0.1"):
		Session.server_url = url   # remember a custom server, but not the local test one
	Session.save()
	_set_status("Connecting to %s..." % url)
	if Net.connect_to_server(url) != OK:
		_set_status("That server address doesn't look right.", Palette.NEGATIVE)


## Runs a server inside this window and joins it. A second window can join with
## the server address ws://localhost:9080.
func _host_local() -> void:
	var err := Net.start_local_server(Session.DEFAULT_PORT)
	if err != OK:
		_set_status("Couldn't start a server on port %d (is one already running?). Connecting to it instead." % Session.DEFAULT_PORT)
	_connect(LOCAL_URL % Session.DEFAULT_PORT)


# --- Room browser --------------------------------------------------------------

func _build_browser() -> void:
	_browser_panel.add_child(_browser_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var frame := UiKit.panel(16)
	frame.add_child(scroll)
	_rooms_list.add_theme_constant_override("separation", 10)
	_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rooms_list)
	_browser_panel.add_child(frame)

	_code_edit.custom_minimum_size = Vector2(200, 0)
	_code_edit.text_submitted.connect(func(_t): _join(_code_edit.text))
	_browser_panel.add_child(_row([UiKit.label("JOIN BY CODE", 26, Palette.TEXT_DIM), _code_edit,
		_button("JOIN", func(): _join(_code_edit.text))]))

	_room_name_edit.custom_minimum_size = Vector2(300, 0)
	_browser_panel.add_child(_row([
		_room_name_edit,
		UiKit.segmented(["2", "3", "4"], 2, func(i: int): _new_cap = i + 2, 26),
		UiKit.toggle("PRIVATE", "PUBLIC", false, func(on: bool): _new_private = on, 26),
		_button("CREATE ROOM", _create),
	], 14))
	_browser_panel.add_child(_row([
		_button("DISCONNECT", func(): Net.disconnect_from_server(), 26),
		_button("REFRESH", func(): Net.send("list_rooms"), 26),
	]))


func _refresh_rooms() -> void:
	for c in _rooms_list.get_children():
		c.queue_free()
	if Net.rooms.is_empty():
		_rooms_list.add_child(UiKit.label("No rooms yet. Create one!", 28, Palette.TEXT_DIM, true))
		return
	for r in Net.rooms:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var code := UiKit.label("PRIVATE" if r.private else str(r.code), 26, Palette.SWAP if r.private else Palette.SCORE)
		code.custom_minimum_size = Vector2(150, 0)
		row.add_child(code)
		var name_label := UiKit.label(str(r.name), 28)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		var host := UiKit.label(str(r.host_name), 24, Palette.TEXT_DIM)
		host.custom_minimum_size = Vector2(190, 0)
		host.clip_text = true
		row.add_child(host)
		row.add_child(UiKit.label("%d/%d" % [int(r.players), int(r.cap)], 28))
		var st := UiKit.label({ "lobby": "WAITING", "playing": "PLAYING", "finished": "FINISHED" }.get(r.state, ""), 22, Palette.TEXT_DIM)
		st.custom_minimum_size = Vector2(130, 0)
		row.add_child(st)
		var join := UiKit.button("JOIN", 24)
		join.disabled = r.state == "playing" or int(r.players) >= int(r.cap)
		join.pressed.connect(func():
			if r.private:
				_code_edit.grab_focus()
				_set_status("%s is private: type its code to join." % r.name)
			else:
				_join(str(r.code)))
		row.add_child(join)
		_rooms_list.add_child(row)


func _join(code: String) -> void:
	code = Protocol.clean_code(code)
	if code.length() != Protocol.CODE_LENGTH:
		_set_status("Room codes have %d letters." % Protocol.CODE_LENGTH, Palette.NEGATIVE)
		return
	_set_status("Joining %s..." % code)
	Net.send("join_room", { "code": code })


func _create() -> void:
	Net.send("create_room", { "name": Protocol.clean_name(_room_name_edit.text, "%s's room" % Session.player_name.left(9)),
		"cap": _new_cap, "private": _new_private })


# --- In a room -------------------------------------------------------------------

func _build_room() -> void:
	_room_panel.add_child(_room_title)
	_room_panel.add_child(UiKit.label("ROOM CODE", 24, Palette.TEXT_DIM, true))
	_room_panel.add_child(_room_code)
	_room_panel.add_child(_room_info)
	var frame := UiKit.panel(20)
	frame.custom_minimum_size = Vector2(700, 0)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_members_list.add_theme_constant_override("separation", 8)
	frame.add_child(_members_list)
	_room_panel.add_child(frame)
	_host_box.add_theme_constant_override("separation", 12)
	_room_panel.add_child(_host_box)
	_room_panel.add_child(_room_hint)
	_start_button.pressed.connect(func(): Net.send("start_game"))
	_room_panel.add_child(_row([_button("LEAVE ROOM", func(): Net.send("leave_room")), _start_button]))


func _refresh_room() -> void:
	var r := Net.room
	var is_host: bool = int(r.host) == int(r.you)
	_room_title.text = str(r.name).to_upper()
	_room_code.text = str(r.code)
	_room_info.text = "%s room  -  up to %d players  -  %s" % ["Private" if r.private else "Public", int(r.cap),
		"share the code with your friends" if r.private else "anyone can join from the list"]
	for c in _members_list.get_children():
		c.queue_free()
	for m in r.members:
		var tag := ""
		if int(m.id) == int(r.host):
			tag += "  (host)"
		if r.state == "finished" and m.rematch:
			tag += "  (ready)"
		if int(m.id) == int(r.you):
			tag += "  (you)"
		_members_list.add_child(UiKit.label(str(m.name) + tag, 32, Palette.TITLE if int(m.id) == int(r.you) else Palette.TEXT, true))
	for k in maxi(0, int(r.cap) - r.members.size()):
		_members_list.add_child(UiKit.label("empty seat", 28, Palette.TEXT_DIM.darkened(0.3), true))

	for c in _host_box.get_children():
		c.queue_free()
	if is_host and r.state == "lobby":
		_host_box.add_child(_row([
			UiKit.label("PLAYERS", 24, Palette.TEXT_DIM),
			UiKit.segmented(["2", "3", "4"], int(r.cap) - 2, func(i: int): Net.send("room_settings", { "cap": i + 2 }), 24),
			UiKit.toggle("PRIVATE", "PUBLIC", bool(r.private), func(on: bool): Net.send("room_settings", { "private": on }), 24),
		], 14))
	if r.state == "finished":
		# Joined after a game ended: the next one starts when everyone in the room is ready.
		var me_ready: bool = r.members.any(func(m): return int(m.id) == int(r.you) and m.rematch)
		_host_box.add_child(_row([UiKit.toggle("READY!", "I'M READY", me_ready, func(on: bool): Net.send("rematch", { "ready": on }), 28)]))
	_start_button.visible = is_host and r.state == "lobby"
	_start_button.disabled = r.members.size() < 2
	if r.state == "playing":
		_room_hint.text = "A game is in progress."
	elif r.state == "finished":
		_room_hint.text = "A game just ended. The next one starts when everyone is ready."
	elif is_host:
		_room_hint.text = "Start when everyone is here." if r.members.size() >= 2 else "Waiting for at least one more player..."
	else:
		_room_hint.text = "Waiting for the host to start the game..."


# --- Which panel -----------------------------------------------------------------

func _refresh() -> void:
	var online := Net.is_online()
	var in_room := online and not Net.room.is_empty()
	_connect_panel.visible = not online
	_browser_panel.visible = online and not in_room
	_room_panel.visible = in_room
	if online:
		_browser_title.text = "ROOMS  -  playing as %s" % str(Net.me.get("name", ""))
		if _status.text.begins_with("Connecting") or _status.text.begins_with("Joining"):
			_set_status("")
		_refresh_rooms()
	if in_room:
		_refresh_room()
