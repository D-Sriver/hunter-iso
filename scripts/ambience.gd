class_name Ambience
extends RefCounted
## Rendu anime commun au hub et aux runs : fond indigo, ombres lavande (jamais noires), couleurs
## sans tonemapping et halo seulement sur ce qui brille vraiment (néons, écrans).

## Réglages à ajuster à l'œil.
const BACKGROUND_COLOR := Color(0.13, 0.09, 0.24)
const AMBIENT_COLOR := Color(0.62, 0.56, 0.9)
const AMBIENT_ENERGY := 0.55
const MOON_COLOR := Color(0.92, 0.9, 1.0)
const MOON_ENERGY := 1.3


static func setup(parent: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	moon.light_color = MOON_COLOR
	moon.light_energy = MOON_ENERGY
	moon.shadow_enabled = true
	parent.add_child(moon)
