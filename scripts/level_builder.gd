class_name LevelBuilder
extends RefCounted
## Construit la géométrie du labyrinthe : sol, murs néon, sorties.
## Placeholders en primitives, remplacés plus tard par les tuiles modélisées dans Blender.

const WALL_HEIGHT := 1.6
const WALL_CAP_HEIGHT := 0.08
const WALL_LAYER := 1

const FLOOR_COLOR := Color(0.09, 0.08, 0.16)
const GAP_COLOR := Color(0.02, 0.01, 0.05)
const WALL_COLOR := Color(0.12, 0.1, 0.22)
const WALL_CAP_COLOR := Color(0.85, 0.2, 1.0)
const EXIT_COLOR := Color(0.2, 1.0, 0.55)


static func build(parent: Node3D, maze: MazeGenerator, tile_size: float) -> void:
	_build_floor(parent, maze, tile_size)
	_build_walls(parent, maze, tile_size)
	_build_exits(parent, maze, tile_size)


static func _build_floor(parent: Node3D, maze: MazeGenerator, tile_size: float) -> void:
	var base := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2((maze.width + 2) * tile_size, (maze.height + 2) * tile_size)
	plane.material = Materials.flat(GAP_COLOR)
	base.mesh = plane
	base.position = Vector3(
		(maze.width - 1) * tile_size * 0.5, -0.11, (maze.height - 1) * tile_size * 0.5
	)
	parent.add_child(base)

	# Une dalle par tuile, légèrement plus petite : les interstices dessinent la grille.
	var slab := BoxMesh.new()
	slab.size = Vector3(tile_size * 0.94, 0.1, tile_size * 0.94)
	slab.material = Materials.flat(FLOOR_COLOR)
	var transforms: Array[Transform3D] = []
	for tile in maze.floor_tiles:
		transforms.append(Transform3D(Basis(), _tile_position(tile, tile_size, -0.05)))
	parent.add_child(_multimesh(slab, transforms))


static func _build_walls(parent: Node3D, maze: MazeGenerator, tile_size: float) -> void:
	var wall_tiles := maze.wall_tiles_touching_floor()

	var block := BoxMesh.new()
	block.size = Vector3(tile_size, WALL_HEIGHT, tile_size)
	block.material = Materials.flat(WALL_COLOR)
	var cap := BoxMesh.new()
	cap.size = Vector3(tile_size, WALL_CAP_HEIGHT, tile_size)
	cap.material = Materials.neon(WALL_CAP_COLOR, 1.2)

	var block_transforms: Array[Transform3D] = []
	var cap_transforms: Array[Transform3D] = []
	for tile in wall_tiles:
		block_transforms.append(
			Transform3D(Basis(), _tile_position(tile, tile_size, WALL_HEIGHT * 0.5))
		)
		cap_transforms.append(
			Transform3D(
				Basis(), _tile_position(tile, tile_size, WALL_HEIGHT + WALL_CAP_HEIGHT * 0.5)
			)
		)
	parent.add_child(_multimesh(block, block_transforms))
	parent.add_child(_multimesh(cap, cap_transforms))

	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(tile_size, WALL_HEIGHT, tile_size)
	for tile in wall_tiles:
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = _tile_position(tile, tile_size, WALL_HEIGHT * 0.5)
		body.add_child(collider)
	parent.add_child(body)


static func _build_exits(parent: Node3D, maze: MazeGenerator, tile_size: float) -> void:
	var pad := BoxMesh.new()
	pad.size = Vector3(tile_size * 0.9, 0.06, tile_size * 0.9)
	pad.material = Materials.neon(EXIT_COLOR, 2.0)
	for tile in maze.exit_tiles:
		var exit_root := Node3D.new()
		exit_root.position = _tile_position(tile, tile_size, 0.0)
		parent.add_child(exit_root)

		var pad_instance := MeshInstance3D.new()
		pad_instance.mesh = pad
		pad_instance.position.y = 0.03
		exit_root.add_child(pad_instance)

		var light := OmniLight3D.new()
		light.light_color = EXIT_COLOR
		light.light_energy = 2.0
		light.omni_range = 4.0
		light.position.y = 1.0
		exit_root.add_child(light)

		var label := Label3D.new()
		label.text = "SORTIE"
		label.modulate = EXIT_COLOR
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 40
		label.outline_size = 8
		label.pixel_size = 0.01
		label.position.y = 2.2
		exit_root.add_child(label)


static func _multimesh(mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance


static func _tile_position(tile: Vector2i, tile_size: float, y: float) -> Vector3:
	return Vector3(tile.x * tile_size, y, tile.y * tile_size)
