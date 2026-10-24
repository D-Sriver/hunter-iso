shader_type spatial;
// Brouillard de guerre : un quad plein écran retrouve, pour chaque pixel, le point du monde
// qu'il montre (via la profondeur) et l'assombrit d'après la carte de vision.
// Jamais vu : noir. Déjà vu : voile gris. Dans le champ (ou vu il y a un instant) : normal.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled,
	shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D vision_map : filter_linear, repeat_disable;
uniform vec2 map_origin;
uniform vec2 map_size;
uniform vec4 void_color : source_color = vec4(0.02, 0.01, 0.05, 1.0);
uniform vec4 veil_color : source_color = vec4(0.16, 0.15, 0.22, 0.62);
// Au-dessus des murs (faisceau d'alerte), rien n'est caché.
uniform float max_height = 3.5;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;

	vec2 uv = (world.xz - map_origin) / map_size;
	bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
	vec4 vision = inside ? texture(vision_map, uv) : vec4(0.0);
	float seen_now = clamp(vision.r, 0.0, 1.0);
	float known = clamp(vision.g, 0.0, 1.0);
	if (world.y > max_height) {
		seen_now = 1.0;
	}

	ALBEDO = mix(void_color.rgb, veil_color.rgb, known);
	ALPHA = mix(1.0, veil_color.a, known) * (1.0 - seen_now);
}
