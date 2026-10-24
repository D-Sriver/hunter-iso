shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/cutaway.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.17, 0.2, 0.2);
uniform vec3 groove_color : source_color = vec3(0.05, 0.06, 0.07);
uniform vec3 trim_color : source_color = vec3(0.2, 1.0, 0.85);
uniform vec3 screen_teal : source_color = vec3(0.25, 1.0, 0.8);
uniform vec3 screen_pink : source_color = vec3(1.0, 0.25, 0.65);
uniform float wall_height = 2.6;
uniform float tile_size = 2.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 side_face(vec2 face_uv, float face_key, out vec3 emission) {
	float u = face_uv.x;
	float v = face_uv.y;
	emission = vec3(0.0);

	// Usure : variation par blocs pour casser l'aplat.
	float grime = 0.85 + 0.3 * hash21(floor(vec2(u * 3.0, v * 3.0)) + face_key);
	vec3 color = base_color * grime;

	// Plinthe à aérations en bas, bandeau en haut.
	if (v < 0.4) {
		color *= step(0.5, fract(u * 6.0)) * 0.35 + 0.55;
	}
	float panel_u = fract(u);
	bool groove = panel_u < 0.025 || panel_u > 0.975
		|| abs(v - 0.4) < 0.02 || abs(v - (wall_height - 0.35)) < 0.02;
	if (groove) {
		color = groove_color;
	}

	// Liseré néon sous le bandeau du haut.
	if (abs(v - (wall_height - 0.2)) < 0.025) {
		emission += trim_color * 0.9;
		color = trim_color * 0.3;
	}

	// Un panneau sur six porte un écran allumé, avec lignes de balayage et faux texte.
	vec2 panel_key = vec2(floor(u), face_key);
	float panel_roll = hash21(panel_key);
	bool on_screen = panel_roll > 0.83 && v > 1.0 && v < 1.75 && panel_u > 0.12 && panel_u < 0.88;
	if (on_screen) {
		vec3 tint = hash21(panel_key + 7.3) > 0.4 ? screen_teal : screen_pink;
		float scanline = 0.75 + 0.25 * step(0.5, fract(v * 40.0));
		float text = step(0.55, hash21(floor(vec2(panel_u * 12.0, v * 18.0)) + panel_key));
		float glow = (0.35 + 0.65 * text) * scanline;
		color = tint * 0.15;
		emission += tint * glow * 1.4;
	}
	return color;
}

void fragment() {
	if (is_cut_away(world_position, FRAGCOORD.xy)) {
		discard;
	}
	vec3 emission = vec3(0.0);
	vec3 color;
	if (!FRONT_FACING) {
		// Intérieur d'un mur rogné : on le peint comme une tranche pleine.
		color = groove_color * 0.7;
	} else if (abs(world_normal.y) > 0.5) {
		// Dessus des murs : sombre, avec un fin contour pour lire le plan du labyrinthe.
		vec2 cell = fract(world_position.xz / tile_size + 0.5);
		float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
		color = groove_color * 1.4;
		emission = trim_color * (1.0 - smoothstep(0.0, 0.03, edge)) * 0.35;
	} else {
		bool faces_x = abs(world_normal.x) > 0.5;
		float u = faces_x ? world_position.z : world_position.x;
		float depth = faces_x ? world_position.x : world_position.z;
		float face_key = round(depth) * 3.0 + sign(faces_x ? world_normal.x : world_normal.z);
		color = side_face(vec2(u, world_position.y), face_key, emission);
	}
	ALBEDO = color;
	EMISSION = emission;
	ROUGHNESS = 0.75;
	METALLIC = 0.2;
}
