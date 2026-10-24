class_name Decor
extends RefCounted
## Habille le niveau : enseignes néon sur les murs visibles et mobilier des salles.

const SIGN_CHANCE := 0.08
const SIGN_HEIGHT := 1.9
const SIGN_SIZE := Vector2(1.3, 0.4)
const SIGN_SHADER := preload("res://shaders/neon_sign.gdshader")
const PROP_SHADER := preload("res://shaders/prop.gdshader")
const RACK_COLOR := Color(0.1, 0.12, 0.13)
const PILLAR_COLOR := Color(0.16, 0.17, 0.18)
const TABLE_COLOR := Color(0.2, 0.22, 0.24)
const NEON_PINK := Color(1.0, 0.25, 0.65)
const NEON_TEAL := Color(0.25, 1.0, 0.8)
const CRATE_COLOR := Color(0.75, 0.33, 0.12)
const TERMINAL_COLOR := Color(0.13, 0.15, 0.16)
## La caméra regarde depuis +X +Z : seules les faces tournées vers elle sont vues,
## on y accroche les enseignes.
const VISIBLE_FACES := [Vector2i(1, 0), Vector2i(0, 1)]


static func build(
	parent: Node3D, level: LevelGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	_place_signs(parent, level, tile_size, rng)
	_place_furniture(parent, level, tile_size, rng)


static func _place_signs(
	parent: Node3D, level: LevelGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	var materials := [_sign_material(NEON_PINK), _sign_material(NEON_TEAL)]
	var colors := [NEON_PINK, NEON_TEAL]
	var quad := QuadMesh.new()
	quad.size = SIGN_SIZE
	for wall in level.wall_tiles_touching_floor():
		for face in VISIBLE_FACES:
			var floor_side: Vector2i = wall + face
			if not level.is_floor(floor_side) or rng.randf() >= SIGN_CHANCE:
				continue
			var normal := Vector3(face.x, 0.0, face.y)
			var pick := rng.randi_range(0, 1)
			var sign_instance := MeshInstance3D.new()
			sign_instance.mesh = quad
			sign_instance.material_override = materials[pick]
			parent.add_child(sign_instance)
			sign_instance.position = (
				LevelBuilder.tile_position(wall, tile_size, SIGN_HEIGHT)
				+ normal * (tile_size * 0.5 + 0.03)
			)
			sign_instance.rotation.y = atan2(normal.x, normal.z)

			var light := OmniLight3D.new()
			light.light_color = colors[pick]
			light.light_energy = 1.2
			light.omni_range = 3.5
			parent.add_child(light)
			light.position = sign_instance.position + normal * 0.6


static func _place_furniture(
	parent: Node3D, level: LevelGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LevelBuilder.WALL_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	for tile in level.furniture:
		var prop := Node3D.new()
		parent.add_child(prop)
		prop.position = LevelBuilder.tile_position(tile, tile_size, 0.0)
		var footprint := Vector3.ZERO
		match String(level.furniture[tile]):
			"rack":
				footprint = _build_rack(prop)
			"pillar":
				footprint = _build_pillar(prop)
			"table":
				footprint = _build_table(prop)
			"desk":
				footprint = _build_desk(prop, _desk_facing(level, tile))
			_:
				footprint = _build_crates(prop, rng)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = footprint
		collider.shape = shape
		body.add_child(collider)
		collider.global_transform = prop.global_transform.translated_local(
			Vector3(0.0, footprint.y * 0.5, 0.0)
		)


## Baie serveur : assez haute pour cacher un hunter, avec des diodes qui clignotent.
## Les baies d'une même rangée se touchent et forment un mur continu.
static func _build_rack(prop: Node3D) -> Vector3:
	var size := Vector3(1.95, 2.2, 1.1)
	_add_box(prop, size, _prop_material(RACK_COLOR, 1.0))
	return size


static func _build_pillar(prop: Node3D) -> Vector3:
	var size := Vector3(1.1, 2.6, 1.1)
	_add_box(prop, size, _prop_material(PILLAR_COLOR, 0.0))
	var ring_mesh := BoxMesh.new()
	ring_mesh.size = Vector3(1.16, 0.08, 1.16)
	ring_mesh.material = Materials.neon(NEON_PINK, 2.0)
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.position.y = 1.6
	prop.add_child(ring)
	return size


## Paillasse de labo : couverture basse, avec un plateau holographique.
static func _build_table(prop: Node3D) -> Vector3:
	var size := Vector3(1.9, 0.8, 1.6)
	_add_box(prop, size, Materials.flat(TABLE_COLOR))
	var holo_mesh := BoxMesh.new()
	holo_mesh.size = Vector3(1.3, 0.02, 0.9)
	holo_mesh.material = Materials.neon(NEON_TEAL, 1.2)
	var holo := MeshInstance3D.new()
	holo.mesh = holo_mesh
	holo.position.y = size.y + 0.02
	prop.add_child(holo)
	return size


## Bureau adossé au mur du fond, écran tourné vers la salle.
static func _build_desk(prop: Node3D, facing: Vector3) -> Vector3:
	prop.rotation.y = atan2(facing.x, facing.z)
	prop.position -= facing * 0.4
	var size := Vector3(1.6, 0.8, 0.8)
	_add_box(prop, size, Materials.flat(TERMINAL_COLOR))
	var screen_mesh := QuadMesh.new()
	screen_mesh.size = Vector2(0.7, 0.42)
	screen_mesh.material = Materials.neon(NEON_TEAL, 1.6)
	var screen := MeshInstance3D.new()
	screen.mesh = screen_mesh
	screen.position = Vector3(0.0, size.y + 0.3, 0.0)
	prop.add_child(screen)
	return size


## Une à trois caisses en vrac sur la tuile. Retourne l'encombrement du tas.
static func _build_crates(prop: Node3D, rng: RandomNumberGenerator) -> Vector3:
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(0.75, 0.6, 0.75)
	crate_mesh.material = Materials.flat(CRATE_COLOR)
	var count := rng.randi_range(1, 3)
	for i in count:
		var crate := MeshInstance3D.new()
		crate.mesh = crate_mesh
		var on_top := i == 2
		crate.position = Vector3(
			0.0 if on_top else (i - 0.5) * 0.8, 0.9 if on_top else 0.3, rng.randf_range(-0.2, 0.2)
		)
		crate.rotation.y = rng.randf_range(-0.3, 0.3)
		prop.add_child(crate)
	return Vector3(1.6, 1.2 if count == 3 else 0.6, 1.0)


## Les bureaux sont contre le mur du haut ou de gauche de leur salle :
## ils regardent vers l'intérieur.
static func _desk_facing(level: LevelGenerator, tile: Vector2i) -> Vector3:
	var room := level.room_at(tile)
	if room != null and tile.y == room.rect.position.y:
		return Vector3(0.0, 0.0, 1.0)
	return Vector3(1.0, 0.0, 0.0)


static func _add_box(prop: Node3D, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = size.y * 0.5
	prop.add_child(instance)


static func _prop_material(color: Color, led_amount: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PROP_SHADER
	material.set_shader_parameter(&"base_color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter(&"led_amount", led_amount)
	return material


static func _sign_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SIGN_SHADER
	material.set_shader_parameter(&"sign_color", Vector3(color.r, color.g, color.b))
	return material
