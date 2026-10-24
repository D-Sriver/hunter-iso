shader_type spatial;

#include "res://shaders/cutaway.gdshaderinc"

uniform vec3 sign_color : source_color = vec3(1.0, 0.25, 0.65);
uniform float strength = 3.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (is_cut_away(world_position, FRAGCOORD.xy)) {
		discard;
	}
	// Faux caractères : des barres verticales irrégulières, comme une enseigne vue de loin.
	vec2 key = vec2(floor(UV.x * 7.0), floor(world_position.x + world_position.z));
	float column = fract(UV.x * 7.0);
	float glyph = step(0.3, hash21(key)) * step(0.15, column) * step(column, 0.85);
	float border = step(UV.y, 0.08) + step(0.92, UV.y);
	float lit = clamp(glyph * step(0.2, UV.y) * step(UV.y, 0.8) + border, 0.0, 1.0);
	ALBEDO = sign_color * (0.05 + 0.3 * lit);
	EMISSION = sign_color * lit * strength;
}
