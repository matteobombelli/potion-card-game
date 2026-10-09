class_name CardArt
extends RefCounted
## The card art style: sprite textures, colours and how they are tinted.
## CardView builds a card from this, so a new art style is mostly a change here
## (plus new PNGs from tools/export_sprites.sh).

const SHADER := preload("res://shaders/tint.gdshader")

const BACKING := preload("res://assets/sprites/card-backing.png")
const MINUS := preload("res://assets/sprites/negative-value.png")
const DIGITS := [
	preload("res://assets/sprites/0-value.png"),
	preload("res://assets/sprites/1-value.png"),
	preload("res://assets/sprites/2-value.png"),
	preload("res://assets/sprites/3-value.png"),
]
const MODIFIERS := {
	CardData.Modifier.LEFT: preload("res://assets/sprites/modifier-leftside.png"),
	CardData.Modifier.RIGHT: preload("res://assets/sprites/modifier-rightside.png"),
	CardData.Modifier.GLOBAL: preload("res://assets/sprites/modifier-global.png"),
}

## On-screen card height to aim for; the sprite is scaled by a whole number to stay pixel-perfect.
const TARGET_HEIGHT := 200.0

# Everything below is derived from the sprites, so redrawn art at any resolution just works.
static var SCALE: float = maxf(1.0, roundf(TARGET_HEIGHT / BACKING.get_height()))
static var SIZE: Vector2 = Vector2(BACKING.get_size()) * SCALE
## Brightest grey in each greyscale sprite; it maps to the pure tint colour.
static var BACKING_REF: float = _brightest_grey(BACKING)
static var MODIFIER_REF: float = _brightest_grey(MODIFIERS[CardData.Modifier.GLOBAL])
static var _icon_offsets := {}

## Pure colours for the four suits; black cards use a near-black so outlines stay visible.
const CARD_TINTS := [
	Color(1, 0, 0),
	Color(0, 1, 0),
	Color(0, 0, 1),
	Color(1, 1, 0),
	Color(0.23, 0.23, 0.23),
]
const ICON_BLACK := Color(0.06, 0.06, 0.06)
const INK_DARK := Color(0.02, 0.02, 0.02)     # value digits on colour cards
const INK_LIGHT := Color(0.95, 0.93, 1.0)     # value digits on black cards
const BACK_TINT := Color(0.45, 0.36, 0.6)     # face-down card backs (deck stacks, dealing)
const SHADOW_TINT := Color(0.02, 0.0, 0.05)


## Texture for a value's digit (0-9 supported if the sprites exist).
static func digit(value: int) -> Texture2D:
	var n := absi(value)
	if n >= DIGITS.size():
		push_warning("No digit sprite for %d; add assets/sprites/%d-value.png and list it in CardArt.DIGITS" % [n, n])
		return DIGITS.back()
	return DIGITS[n]


static func card_tint(c: int) -> Color:
	return CARD_TINTS[c]


static func icon_tint(c: int) -> Color:
	return ICON_BLACK if c == CardData.CardColor.BLACK else CARD_TINTS[c]


## Bright version of a card colour for particles and text (black -> smoky grey).
static func fx_color(c: int) -> Color:
	return Color(0.55, 0.5, 0.65) if c == CardData.CardColor.BLACK else CARD_TINTS[c]


static func make_material(tint: Color, ref_lum := BACKING_REF, solid := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("ref_lum", ref_lum)
	m.set_shader_parameter("mode", 1 if solid else 0)
	return m


## Offset (in CardView local space) of the modifier icon's centre,
## found from the opaque pixels of the icon sprite.
static func modifier_icon_offset(mod: int) -> Vector2:
	if not MODIFIERS.has(mod):
		return Vector2.ZERO
	if not _icon_offsets.has(mod):
		var tex: Texture2D = MODIFIERS[mod]
		var used := tex.get_image().get_used_rect()
		_icon_offsets[mod] = (Vector2(used.get_center()) - Vector2(tex.get_size()) / 2.0) * SCALE
	return _icon_offsets[mod]


static func _brightest_grey(tex: Texture2D) -> float:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var best := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				best = maxf(best, c.r)
	return best if best > 0.0 else 1.0
