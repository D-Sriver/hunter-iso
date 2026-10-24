shader_type spatial;

#include "res://shaders/cutaway.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.12, 0.14, 0.15);
uniform vec3 led_color : source_color = vec3(0.25, 1.0, 0.8);
uniform float led_amount = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (is_cut_away(world_position, FRAGCOORD.xy)) {
		discard;
	}
	// Façades de baies : rangées de diodes qui clignotent à des rythmes différents.
	float u = abs(world_normal.x) > 0.5 ? world_position.z : world_position.x;
	vec2 led_cell = floor(vec2(u * 6.0, world_position.y * 5.0));
	vec2 led_local = fract(vec2(u * 6.0, world_position.y * 5.0));
	float is_led = step(length(led_local - vec2(0.5)), 0.18) * step(abs(world_normal.y), 0.5);
	float blink = step(0.5, fract(TIME * (0.3 + hash21(led_cell)) + hash21(led_cell + 4.2)));
	float lit = is_led * blink * step(0.45, hash21(led_cell + 9.1)) * led_amount;
	float grime = 0.9 + 0.2 * hash21(floor(world_position.xz * 2.0) + floor(world_position.y * 3.0));
	ALBEDO = mix(base_color * grime, led_color * 0.3, lit);
	EMISSION = led_color * lit * 2.0;
	ROUGHNESS = 0.6;
	METALLIC = 0.4;
}
