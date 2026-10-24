class_name LevelBuilder
extends RefCounted
## Construit le niveau avec les pièces du kit Blender : dalles, murs, poteaux d'angle, sorties.
##
## Vue en diorama : la caméra regarde depuis +X +Z. Les murs au fond des salles (côtés -Z et -X)
## sont des murs pleins ; ceux entre la caméra et le joueur (côtés +Z et +X) sont des murets,
## pour qu'on voie toujours l'intérieur des salles.

const WALL_LAYER := 1
const WALL_HEIGHT := 3.0
const EXIT_COLOR := Color(0.25, 1.0, 0.35)
const ROOM_LABEL_COLOR := Color(0.75, 0.8, 1.0, 0.3)
const ROOM_NAMES := {
	LevelGenerator.RoomKind.START: "QUAI D'ARRIVÉE",
	LevelGenerator.RoomKind.VAULT: "CHAMBRE FORTE",
	LevelGenerator.RoomKind.SERVER: "SALLE SERVEURS",
	LevelGenerator.RoomKind.LAB: "LABORATOIRE",
	LevelGenerator.RoomKind.STORAGE: "ENTREPÔT",
	LevelGenerator.RoomKind.OFFICE: "BUREAUX",
}
## Murs pleins tirés au hasard, avec leur poids.
const WALL_VARIANTS := {
	"wall_panel": 8,
	"wall_pipes": 4,
	"wall_screens": 4,
	"wall_neon_pink": 1,
	"wall_neon_teal": 1,
}
const ROOM_LIGHT_COLORS := [
	Color(1.0, 0.3, 0.65), Color(0.25, 1.0, 0.85), Color(1.0, 0.6, 0.25), Color(0.6, 0.45, 1.0)
]


static func build(
	parent: Node3D, level: LevelGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	_build_floor(parent, level, tile_size)
	_build_walls(parent, level, tile_size, rng)
	_build_colliders(parent, level, tile_size)
	_build_room_lights(parent, level, tile_size, rng)
	_build_room_labels(parent, level, tile_size)
	_build_exits(parent, level, tile_size)


static func tile_position(tile: Vector2i, tile_size: float, y: float) -> Vector3:
	return Vector3(tile.x * tile_size, y, tile.y * tile_size)


static func _build_floor(parent: Node3D, level: LevelGenerator, tile_size: float) -> void:
	for tile in level.ground_tiles():
		var piece := "floor_room" if level.room_at(tile) != null else "floor_corridor"
		_place(parent, piece, tile_position(tile, tile_size, 0.0), 0.0)


## Un mur sur chaque bord entre du sol et du vide. Les murs autour d'une sortie sont des portes
## éclairées en vert, pour la repérer de loin.
static func _build_walls(
	parent: Node3D, level: LevelGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	var half := tile_size * 0.5
	var posts := {}
	for tile in level.ground_tiles():
		var center := tile_position(tile, tile_size, 0.0)
		var near_exit := level.exit_tiles.has(tile)
		for dir: Vector2i in LevelGenerator.DIRECTIONS:
			if level.is_ground(tile + dir):
				continue
			var edge := center + Vector3(dir.x, 0.0, dir.y) * half
			var along_x := dir.y != 0
			var rotation := 0.0 if along_x else PI / 2.0
			var faces_camera := dir.x > 0 or dir.y > 0
			if faces_camera:
				_place(parent, "wall_stub", edge, rotation)
				continue
			var piece := "wall_door" if near_exit else _pick_wall(rng)
			_place(parent, piece, edge, rotation)
			# Poteaux aux deux bouts du mur : ils cachent les jonctions dans les angles.
			var side := Vector3(half, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, half)
			for end in [edge - side, edge + side]:
				posts[Vector2i(roundi(end.x * 2.0), roundi(end.z * 2.0))] = end
	for post: Vector3 in posts.values():
		_place(parent, "wall_post", post, 0.0)


static func _pick_wall(rng: RandomNumberGenerator) -> String:
	var total := 0
	for weight: int in WALL_VARIANTS.values():
		total += weight
	var roll := rng.randi_range(1, total)
	for piece: String in WALL_VARIANTS:
		roll -= WALL_VARIANTS[piece]
		if roll <= 0:
			return piece
	return "wall_panel"


## Collisions : un bloc par case de mur, aligné sur le bord des dalles comme les murs visibles.
static func _build_colliders(parent: Node3D, level: LevelGenerator, tile_size: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(tile_size, WALL_HEIGHT, tile_size)
	for tile in level.wall_tiles_touching_floor():
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = tile_position(tile, tile_size, WALL_HEIGHT * 0.5)
		body.add_child(collider)
	parent.add_child(body)


## Une ou deux lumières colorées par salle, contre les murs du fond : c'est elles qui donnent
## les reflets rose et cyan.
static func _build_room_lights(
	parent: Node3D, level: LevelGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	for room in level.rooms:
		var r := room.rect
		var spots := [
			Vector2i(r.position.x + r.size.x / 4, r.position.y),
			Vector2i(r.position.x, r.position.y + r.size.y * 3 / 4),
		]
		for spot: Vector2i in spots.slice(0, rng.randi_range(1, 2)):
			var light := OmniLight3D.new()
			light.light_color = ROOM_LIGHT_COLORS[rng.randi_range(0, ROOM_LIGHT_COLORS.size() - 1)]
			light.light_energy = 2.0
			light.omni_range = 7.0
			light.position = tile_position(spot, tile_size, 2.4)
			parent.add_child(light)


## Nom de la salle peint au sol, orienté pour se lire de gauche à droite à l'écran.
static func _build_room_labels(parent: Node3D, level: LevelGenerator, tile_size: float) -> void:
	for room in level.rooms:
		var label := Label3D.new()
		label.text = ROOM_NAMES[room.kind]
		label.modulate = ROOM_LABEL_COLOR
		label.font_size = 72
		label.pixel_size = 0.01
		label.outline_size = 0
		parent.add_child(label)
		var back_row := Vector2i(room.center().x, room.rect.position.y + 1)
		label.position = tile_position(back_row, tile_size, 0.02)
		label.rotation = Vector3(-PI / 2.0, PI / 4.0, 0.0)


static func _build_exits(parent: Node3D, level: LevelGenerator, tile_size: float) -> void:
	for tile in level.exit_tiles:
		var exit_root := _place(parent, "exit_pad", tile_position(tile, tile_size, 0.0), 0.0)

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
		label.position.y = WALL_HEIGHT + 0.4
		exit_root.add_child(label)


static func _place(parent: Node3D, piece: String, at: Vector3, rotation_y: float) -> Node3D:
	var node := Kit.spawn(piece)
	parent.add_child(node)
	node.position = at
	node.rotation.y = rotation_y
	return node
