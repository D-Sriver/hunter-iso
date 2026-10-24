// Coupe les murs placés entre la caméra et le joueur, pour qu'il reste visible dans le labyrinthe.
// La caméra regarde depuis la diagonale +X +Z : tout ce qui est de ce côté du joueur est rogné.

global uniform vec3 player_position;

const float CUT_HALF_WIDTH = 5.5;
const float CUT_DEPTH = 14.0;
const float CUT_STUB_HEIGHT = 0.3;

float cutaway_amount(vec3 pos) {
	vec3 offset = pos - player_position;
	float toward_camera = (offset.x + offset.z) * 0.70710678;
	float sideways = abs(offset.x - offset.z) * 0.70710678;
	float in_front = smoothstep(-0.6, 0.4, toward_camera)
		* (1.0 - smoothstep(CUT_DEPTH - 2.0, CUT_DEPTH, toward_camera));
	float in_lane = 1.0 - smoothstep(CUT_HALF_WIDTH - 1.5, CUT_HALF_WIDTH, sideways);
	return in_front * in_lane;
}

// Bord tramé plutôt que net : la coupe se fond au lieu de clignoter.
bool is_cut_away(vec3 pos, vec2 frag_coord) {
	if (pos.y <= CUT_STUB_HEIGHT) {
		return false;
	}
	float dither = fract(52.9829189 * fract(0.06711056 * frag_coord.x + 0.00583715 * frag_coord.y));
	return cutaway_amount(pos) > dither;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
