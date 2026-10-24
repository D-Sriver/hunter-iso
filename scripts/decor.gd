class_name Decor
extends RefCounted
## Habille le labyrinthe : enseignes néon sur les murs visibles,
## caisses et terminaux contre les murs du fond.

const SIGN_CHANCE := 0.08
const CORRIDOR_PROP_CHANCE := 0.15
const NOOK_PROP_CHANCE := 0.4
const TERMINAL_CHANCE := 0.4
const SIGN_HEIGHT := 1.9
const SIGN_SIZE := Vector2(1.3, 0.4)
const PROP_OFFSET := 0.72
const SIGN_SHADER := preload("res://shaders/neon_sign.gdshader")
const NEON_PINK := Color(1.0, 0.25, 0.65)
const NEON_TEAL := Color(0.25, 1.0, 0.8)
const CRATE_COLOR := Color(0.75, 0.33, 0.12)
const TERMINAL_COLOR := Color(0.13, 0.15, 0.16)
## La caméra regarde depuis +X +Z : seules les faces tournées vers elle sont vues,
## on y accroche les enseignes.
const VISIBLE_FACES := [Vector2i(1, 0), Vector2i(0, 1)]
## Murs du fond, à l'opposé de la caméra : le mobilier s'y adosse pour ne pas masquer le joueur.
const BACK_WALLS := [Vector2i(-1, 0), Vector2i(0, -1)]


static func build(
	parent: Node3D,
	maze: MazeGenerator,
	tile_size: float,
	reserved: Array[Vector2i],
	rng: RandomNumberGenerator
) -> void:
	_place_signs(parent, maze, tile_size, rng)
	_place_props(parent, maze, tile_size, reserved, rng)


static func _place_signs(
	parent: Node3D, maze: MazeGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	var materials := [_sign_material(NEON_PINK), _sign_material(NEON_TEAL)]
	var colors := [NEON_PINK, NEON_TEAL]
	var quad := QuadMesh.new()
	quad.size = SIGN_SIZE
	for wall in maze.wall_tiles_touching_floor():
		for face in VISIBLE_FACES:
			var floor_side: Vector2i = wall + face
			if not maze.is_floor(floor_side) or rng.randf() >= SIGN_CHANCE:
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


static func _place_props(
	parent: Node3D,
	maze: MazeGenerator,
	tile_size: float,
	reserved: Array[Vector2i],
	rng: RandomNumberGenerator
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LevelBuilder.WALL_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	for tile in maze.floor_tiles:
		if reserved.has(tile):
			continue
		var back_walls: Array[Vector2i] = []
		for dir in BACK_WALLS:
			if not maze.is_floor(tile + dir):
				back_walls.append(dir)
		if back_walls.is_empty():
			continue
		var chance := NOOK_PROP_CHANCE if _open_sides(maze, tile) != 2 else CORRIDOR_PROP_CHANCE
		if rng.randf() >= chance:
			continue
		var wall_dir: Vector2i = back_walls[rng.randi_range(0, back_walls.size() - 1)]
		var toward_wall := Vector3(wall_dir.x, 0.0, wall_dir.y)
		var prop := Node3D.new()
		parent.add_child(prop)
		prop.position = LevelBuilder.tile_position(tile, tile_size, 0.0) + toward_wall * PROP_OFFSET
		# L'avant du meuble (+Z local) regarde à l'opposé du mur.
		prop.rotation.y = atan2(-toward_wall.x, -toward_wall.z)
		var size := (
			_build_terminal(prop) if rng.randf() < TERMINAL_CHANCE else _build_crates(prop, rng)
		)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		collider.global_transform = prop.global_transform.translated_local(
			Vector3(0.0, size.y * 0.5, 0.0)
		)


## Retourne l'encombrement du terminal, pour sa collision.
static func _build_terminal(prop: Node3D) -> Vector3:
	var size := Vector3(0.7, 1.1, 0.35)
	var case_mesh := BoxMesh.new()
	case_mesh.size = size
	case_mesh.material = Materials.flat(TERMINAL_COLOR)
	var case_instance := MeshInstance3D.new()
	case_instance.mesh = case_mesh
	case_instance.position.y = size.y * 0.5
	prop.add_child(case_instance)

	var screen_mesh := QuadMesh.new()
	screen_mesh.size = Vector2(0.5, 0.32)
	screen_mesh.material = Materials.neon(NEON_TEAL, 1.6)
	var screen := MeshInstance3D.new()
	screen.mesh = screen_mesh
	screen.position = Vector3(0.0, 0.8, size.z * 0.5 + 0.01)
	prop.add_child(screen)
	return size


## Une caisse, parfois deux empilées. Retourne l'encombrement de la pile.
static func _build_crates(prop: Node3D, rng: RandomNumberGenerator) -> Vector3:
	var size := Vector3(0.55, 0.5, 0.5)
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = size
	crate_mesh.material = Materials.flat(CRATE_COLOR)
	var bottom := MeshInstance3D.new()
	bottom.mesh = crate_mesh
	bottom.position.y = size.y * 0.5
	prop.add_child(bottom)
	if rng.randf() < 0.4:
		var top := MeshInstance3D.new()
		top.mesh = crate_mesh
		top.position = Vector3(0.05, size.y * 1.5, 0.0)
		top.rotation.y = rng.randf_range(-0.4, 0.4)
		prop.add_child(top)
		return Vector3(size.x, size.y * 2.0, size.z)
	return size


static func _open_sides(maze: MazeGenerator, tile: Vector2i) -> int:
	var count := 0
	for dir in MazeGenerator.DIRECTIONS:
		if maze.is_floor(tile + dir):
			count += 1
	return count


static func _sign_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SIGN_SHADER
	material.set_shader_parameter(&"sign_color", Vector3(color.r, color.g, color.b))
	return material
