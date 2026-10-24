shader_type spatial;

#include "res://shaders/cutaway.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.07, 0.085, 0.09);
uniform vec3 groove_color : source_color = vec3(0.03, 0.035, 0.04);
uniform vec3 circuit_color : source_color = vec3(0.15, 1.0, 0.75);
uniform float circuit_strength = 1.1;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Pistes de circuit : segments de 4 cases sur une grille de 50 cm, avec une pastille au départ.
float circuit_traces(vec2 p) {
	vec2 cell = floor(p * 2.0);
	vec2 local = fract(p * 2.0);
	float trace = 0.0;

	vec2 row_chunk = vec2(floor(cell.x / 4.0), cell.y);
	if (hash21(row_chunk) < 0.22) {
		trace = max(trace, 1.0 - smoothstep(0.03, 0.07, abs(local.y - 0.5)));
		if (mod(cell.x, 4.0) < 0.5) {
			trace = max(trace, 1.0 - smoothstep(0.1, 0.15, length(local - vec2(0.5))));
		}
	}
	vec2 column_chunk = vec2(cell.x, floor(cell.y / 4.0)) + 31.7;
	if (hash21(column_chunk) < 0.18) {
		trace = max(trace, 1.0 - smoothstep(0.03, 0.07, abs(local.x - 0.5)));
	}
	return trace;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 slab = fract(p);
	float slab_edge = min(min(slab.x, 1.0 - slab.x), min(slab.y, 1.0 - slab.y));
	vec3 color = base_color * (0.9 + 0.2 * hash21(floor(p)));
	if (slab_edge < 0.015) {
		color = groove_color;
	}
	float trace = circuit_traces(p);
	float pulse = 0.65 + 0.35 * sin(TIME * 1.5 + hash21(floor(p * 0.5)) * 6.2831);
	ALBEDO = mix(color, circuit_color * 0.25, trace);
	EMISSION = circuit_color * trace * pulse * circuit_strength;
	ROUGHNESS = 0.6;
	METALLIC = 0.3;
}
