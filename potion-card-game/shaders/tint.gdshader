shader_type canvas_item;
// Recolours the greyscale card sprites.
//  mode 0 (gradient): tint * (grey / ref_lum), so the brightest grey becomes the pure tint.
//  mode 1 (solid):    every opaque pixel becomes the tint.
// outline > 0 draws a 1-texel outline (outline_color) around opaque pixels, so an icon
// stays readable on a card face of the same colour.

uniform vec4 tint : source_color = vec4(1.0);
uniform float ref_lum = 0.396;
uniform int mode = 0;
uniform float outline = 0.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

// COLOR in fragment() already includes the texture sample, so keep the plain
// vertex colour (modulate) separately.
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = mode == 0 ? tint.rgb * clamp(tex.r / ref_lum, 0.0, 1.0) : tint.rgb;
	vec4 result = vec4(col, tex.a * tint.a);

	if (outline > 0.0 && tex.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float n = texture(TEXTURE, UV + vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a
			+ texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (n > 0.5) {
			result = vec4(outline_color.rgb, outline_color.a * outline);
		}
	}

	result.rgb = mix(result.rgb, flash_color.rgb, flash);
	COLOR = result * vertex_color;
}
