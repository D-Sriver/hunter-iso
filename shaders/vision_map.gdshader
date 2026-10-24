shader_type canvas_item;
// Carte de vision vue de dessus, recalculée à chaque image et pour chaque pixel.
// R : vu récemment (vaut `hold` dans le champ, puis décroît) ; G : déjà exploré.
// L'image précédente est relue via la texture d'écran : le viewport n'est jamais effacé.
render_mode blend_disabled;

uniform sampler2D previous : hint_screen_texture, filter_nearest;
uniform sampler2D opacity : filter_nearest;
uniform ivec2 grid_size;
uniform float cell_size;
uniform vec2 map_origin;
uniform vec2 map_size;
uniform vec2 eye;
uniform vec2 heading = vec2(0.0, 1.0);
uniform float cone_cos_outer;
uniform float cone_cos_inner;
uniform float cone_range;
uniform float around_range;
uniform float hold = 1.75;
uniform float decay;

bool is_opaque(ivec2 cell) {
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, grid_size))) {
		return true;
	}
	return texelFetch(opacity, cell, 0).r > 0.5;
}

// Parcourt les cellules entre l'œil et le point : la cellule d'arrivée peut être un mur
// (on voit sa face), mais aucune de celles d'avant.
bool has_line_of_sight(vec2 from, vec2 to) {
	vec2 a = (from - map_origin) / cell_size;
	vec2 b = (to - map_origin) / cell_size;
	ivec2 cell = ivec2(floor(a));
	ivec2 goal = ivec2(floor(b));
	vec2 d = b - a;
	ivec2 stp = ivec2(sign(d));
	vec2 inv = vec2(
		abs(d.x) > 1e-6 ? 1.0 / abs(d.x) : 1e9,
		abs(d.y) > 1e-6 ? 1.0 / abs(d.y) : 1e9
	);
	vec2 f = a - floor(a);
	vec2 t_max = vec2(d.x > 0.0 ? 1.0 - f.x : f.x, d.y > 0.0 ? 1.0 - f.y : f.y) * inv;
	for (int i = 0; i < 96; i++) {
		if (all(equal(cell, goal))) {
			return true;
		}
		if (t_max.x < t_max.y) {
			t_max.x += inv.x;
			cell.x += stp.x;
		} else {
			t_max.y += inv.y;
			cell.y += stp.y;
		}
		if (all(equal(cell, goal))) {
			return true;
		}
		if (is_opaque(cell)) {
			return false;
		}
	}
	return true;
}

void fragment() {
	vec2 world = map_origin + UV * map_size;
	vec2 to_point = world - eye;
	float dist = length(to_point);
	float facing = dot(to_point / max(dist, 1e-4), heading);
	float cone = smoothstep(cone_cos_outer, cone_cos_inner, facing);
	cone *= 1.0 - smoothstep(cone_range - 2.0, cone_range, dist);
	float around = 1.0 - smoothstep(around_range - 1.0, around_range, dist);
	float visible = max(cone, around);
	if (visible > 0.0 && !has_line_of_sight(eye, world)) {
		visible = 0.0;
	}

	vec4 last = texture(previous, SCREEN_UV);
	float recent = max(visible * hold, last.r - decay);
	float known = max(last.g, visible);
	COLOR = vec4(recent, known, 0.0, 1.0);
}
