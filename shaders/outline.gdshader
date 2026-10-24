shader_type spatial;
// Contour façon anime : la coque du modèle, gonflée le long des normales et vue de l'intérieur,
// dessine un trait sombre autour de la silhouette.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.06, 0.03, 0.14, 1.0);
uniform float thickness = 0.018;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
