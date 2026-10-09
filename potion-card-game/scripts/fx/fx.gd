extends Node
## Autoload "Fx": screen shake, hit-stop, particles, floating text, banners and the
## shared font. Each scene registers its layers with use_scene() (TableRoot does it).

var world: Node2D       # world-space effects layer of the current scene
var ui: CanvasLayer     # screen-space layer for banners
var camera: Camera2D    # shaken by shake()
var font: Font

var hitstop_enabled := true  # the headless autoplay test disables this

var _trauma := 0.0
var _pixel: Texture2D
var _soft: Texture2D
var _hitstop_until := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_pixel = ImageTexture.create_from_image(img)
	_soft = _make_soft_circle(32)

	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Futura", "Avenir Next", "Arial Rounded MT Bold", "Helvetica Neue", "Arial"])
	f.font_weight = 800
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font = f
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 28
	get_tree().root.theme = theme


func use_scene(p_world: Node2D, p_ui: CanvasLayer, p_camera: Camera2D) -> void:
	world = p_world
	ui = p_ui
	camera = p_camera
	_trauma = 0.0
	_hitstop_until = 0
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	if is_instance_valid(camera):
		var s := _trauma * _trauma
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 30.0 * s
		camera.rotation = randf_range(-1, 1) * 0.015 * s
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0


# --- Camera -----------------------------------------------------------------

func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


## Freezes the game almost completely for a few frames to sell an impact.
func hitstop(seconds := 0.06) -> void:
	if not hitstop_enabled:
		return
	Engine.time_scale = 0.03
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(seconds * 1000.0))


# --- Particles --------------------------------------------------------------

func _particles(pos: Vector2, amount: int, life: float, parent: Node = null) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.texture = _pixel
	p.local_coords = false
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.7, Color(1, 1, 1, 0.9))
	p.color_ramp = ramp
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = shrink
	_add_world(p, parent)
	p.emitting = true
	get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)
	return p


func _add_world(n: Node, parent: Node = null) -> void:
	if parent and is_instance_valid(parent):
		parent.add_child(n)
	elif is_instance_valid(world):
		world.add_child(n)
	else:
		get_tree().current_scene.add_child(n)


## Radial spark burst.
func burst(pos: Vector2, color: Color, amount := 24, speed := 420.0, life := 0.55, size := 2.0, gravity := 900.0) -> CPUParticles2D:
	var p := _particles(pos, amount, life)
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 80.0
	p.damping_max = 200.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.4
	p.color = color
	return p


## Puffs that shoot sideways along the bottom edge of a card.
func dust(pos: Vector2, width := 96.0, color := Palette.DUST) -> void:
	for dir in [-1.0, 1.0]:
		var p := _particles(pos + Vector2(dir * width * 0.35, 0), 14, 0.5)
		p.texture = _soft
		p.direction = Vector2(dir, -0.25)
		p.spread = 20.0
		p.initial_velocity_min = 160.0
		p.initial_velocity_max = 380.0
		p.damping_min = 500.0
		p.damping_max = 800.0
		p.gravity = Vector2(0, -60)
		p.scale_amount_min = 0.35
		p.scale_amount_max = 0.8
		p.color = Color(color, 0.7)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(width * 0.15, 4)


## Slow, swelling dark smoke for black cards.
func smoke(pos: Vector2, amount := 18) -> void:
	var p := _particles(pos, amount, 1.1)
	p.texture = _soft
	p.explosiveness = 0.85
	p.spread = 180.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 180.0
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.gravity = Vector2(0, -90)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(40, 55)
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = grow
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.8
	p.color = Palette.SMOKE


## Multicoloured confetti fountain. Pass `parent` to draw it inside an overlay.
func confetti(pos: Vector2, colors: Array, amount := 60, speed := 900.0, parent: Node = null) -> void:
	var p := _particles(pos, amount, 1.6, parent)
	p.direction = Vector2.UP
	p.spread = 50.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 1100)
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.scale_amount_curve = null
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	p.color_initial_ramp = g


## A particle emitter that follows `target` until stopped. Call stop_trail() when done.
func trail(target: Node2D, color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 0.45
	p.texture = _pixel
	p.local_coords = false
	p.spread = 180.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector2.ZERO
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(36, 50)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.show_behind_parent = true
	target.add_child(p)
	return p


func stop_trail(p: CPUParticles2D) -> void:
	if not is_instance_valid(p):
		return
	p.emitting = false
	get_tree().create_timer(p.lifetime + 0.1, false).timeout.connect(p.queue_free)


# --- Composite -------------------------------------------------------------

## A card lands on the table. Colour cards get a light thud; black cards are the
## one heavy hit in the game (freeze frame, shake, smoke).
func card_impact(v: CardView) -> void:
	var pos := v.global_position
	if not v.card.is_black():
		v.squash(0.6)
		shake(0.12)
		dust(pos + Vector2(0, CardArt.SIZE.y / 2.0), CardArt.SIZE.x)
		return
	v.squash(1.2)
	v.flash(0.6, 0.2)
	hitstop(0.06)
	shake(0.45)
	smoke(pos, 20)
	ring(pos, Palette.BLACK_RING, 220.0, 12.0, 0.45)


# --- Shapes -----------------------------------------------------------------

## Expanding shockwave ring.
func ring(pos: Vector2, color: Color, radius := 120.0, width := 10.0, duration := 0.35) -> void:
	var r := Shockwave.new()
	r.position = pos
	r.color = color
	r.width = width
	_add_world(r)
	var t := r.create_tween().set_parallel()
	t.tween_property(r, "radius", radius, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(r, "alpha", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(r.queue_free)


## Jagged lightning line from a to b.
func zap(a: Vector2, b: Vector2, color: Color) -> void:
	var line := Line2D.new()
	var steps := 7
	var normal := (b - a).orthogonal().normalized()
	for i in steps + 1:
		var t := float(i) / steps
		var jitter := 0.0 if i == 0 or i == steps else randf_range(-18, 18)
		line.add_point(a.lerp(b, t) + normal * jitter)
	line.width = 7.0
	line.default_color = color.lightened(0.35)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 20
	_add_world(line)
	var core := line.duplicate() as Line2D
	core.width = 2.5
	core.default_color = Color.WHITE
	line.add_child(core)
	core.position = Vector2.ZERO
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.3).set_delay(0.08)
	tw.tween_callback(line.queue_free)
	burst(b, color, 14, 300.0, 0.4, 1.5, 600.0)


# --- Text -------------------------------------------------------------------

func label_settings(size: int, color := Color.WHITE, outline := 10) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Palette.TEXT_OUTLINE
	ls.shadow_size = 0
	ls.shadow_color = Color(0, 0, 0, 0.5)
	ls.shadow_offset = Vector2(0, 5)
	return ls


## Number/text that pops, rises and fades in world space.
func float_text(pos: Vector2, text: String, color := Color.WHITE, size := 44, rise := 80.0, duration := 0.9) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = 30
	var l := Label.new()
	l.text = text
	l.label_settings = label_settings(size, color)
	holder.add_child(l)
	_add_world(holder)
	l.position = -l.get_minimum_size() / 2.0
	holder.scale = Vector2.ZERO
	var t := holder.create_tween()
	t.tween_property(holder, "scale", Vector2.ONE * 1.25, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(holder, "scale", Vector2.ONE, 0.1)
	t.parallel().tween_property(holder, "position:y", pos.y - rise, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(holder, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	t.tween_callback(holder.queue_free)


## Big centred text that slams in, holds, then flies off. Await the returned signal.
func banner(text: String, color := Color.WHITE, hold := 0.8, size := 120, at := Vector2(-1, -1)) -> Signal:
	var holder := Node2D.new()
	var vp := get_viewport().get_visible_rect().size
	holder.position = vp / 2.0 if at.x < 0 else at
	var l := Label.new()
	l.text = text
	l.label_settings = label_settings(size, color, 18)
	l.label_settings.shadow_size = 1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(l)
	if is_instance_valid(ui):
		ui.add_child(holder)
	else:
		get_tree().current_scene.add_child(holder)
	l.position = -l.get_minimum_size() / 2.0
	holder.scale = Vector2.ONE * 3.0
	holder.modulate.a = 0.0
	holder.rotation = -0.08
	var t := holder.create_tween()
	t.set_parallel()
	t.tween_property(holder, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(holder, "modulate:a", 1.0, 0.1)
	t.tween_property(holder, "rotation", 0.0, 0.16)
	t.chain().tween_callback(func(): shake(0.15))
	t.tween_property(holder, "scale", Vector2(1.06, 0.94), 0.06)
	t.chain().tween_property(holder, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(hold)
	t.chain().tween_property(holder, "position:y", holder.position.y - 60, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(holder, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(holder.queue_free)
	return t.finished


## Big title that slams in and keeps gently breathing. Returns the holder so
## callers can attach more nodes (e.g. a subtitle) under it.
func slam_title(parent: Node, text: String, at: Vector2, size := 110, color := Palette.TITLE) -> Node2D:
	var holder := Node2D.new()
	holder.position = at
	var l := Label.new()
	l.text = text
	l.label_settings = label_settings(size, color, 18)
	holder.add_child(l)
	parent.add_child(holder)
	l.position = -l.get_minimum_size() / 2.0
	holder.scale = Vector2.ONE * 3.0
	holder.modulate.a = 0.0
	holder.rotation = 0.08
	var t := holder.create_tween().set_parallel()
	t.tween_property(holder, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(holder, "modulate:a", 1.0, 0.1)
	t.tween_property(holder, "rotation", 0.0, 0.18)
	t.chain().tween_callback(func(): shake(0.35))
	t.chain().tween_callback(func():
		var breathe := holder.create_tween().set_loops()
		breathe.tween_property(holder, "scale", Vector2.ONE * 1.03, 1.2).set_trans(Tween.TRANS_SINE)
		breathe.tween_property(holder, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE))
	return holder


func soft_texture() -> Texture2D:
	return _soft


func _make_soft_circle(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
