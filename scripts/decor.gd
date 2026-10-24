class_name Decor
extends RefCounted
## Meuble les salles avec les pièces du kit, d'après le plan de mobilier du générateur.


static func build(
	parent: Node3D, level: LevelGenerator, tile_size: float, rng: RandomNumberGenerator
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LevelBuilder.WALL_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	for tile: Vector2i in level.furniture:
		var prop := Node3D.new()
		parent.add_child(prop)
		prop.position = LevelBuilder.tile_position(tile, tile_size, 0.0)
		var footprint := Vector3.ZERO
		match String(level.furniture[tile]):
			"rack":
				footprint = _build_racks(prop)
			"pillar":
				footprint = _add(prop, "pillar", Vector3(0.9, 3.0, 0.9))
			"table":
				footprint = _add(prop, "lab_table", Vector3(1.8, 1.0, 1.2))
			"desk":
				footprint = _build_desk(prop, _desk_facing(level, tile))
			_:
				footprint = _build_clutter(prop, rng)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = footprint
		collider.shape = shape
		body.add_child(collider)
		collider.global_transform = prop.global_transform.translated_local(
			Vector3(0.0, footprint.y * 0.5, 0.0)
		)


## Deux baies serveur par tuile : une rangée forme un mur continu, assez haut pour cacher
## un hunter.
static func _build_racks(prop: Node3D) -> Vector3:
	for offset in [-0.47, 0.47]:
		var rack := Kit.spawn("server_rack")
		prop.add_child(rack)
		rack.position.x = offset
	return Vector3(1.95, 2.2, 1.0)


## Bureau adossé au mur du fond, écrans tournés vers la salle, avec un terminal à côté.
static func _build_desk(prop: Node3D, facing: Vector3) -> Vector3:
	prop.rotation.y = atan2(facing.x, facing.z)
	prop.position -= facing * 0.5
	var desk := Kit.spawn("desk")
	prop.add_child(desk)
	return Vector3(1.6, 1.0, 0.8)


## Caisses, pile de caisses ou bidon, posés de travers.
static func _build_clutter(prop: Node3D, rng: RandomNumberGenerator) -> Vector3:
	var pieces := ["crate", "crate_stack", "barrel"]
	var sizes := [Vector3(0.8, 0.8, 0.8), Vector3(1.7, 1.5, 0.9), Vector3(0.6, 0.9, 0.6)]
	var pick := rng.randi_range(0, pieces.size() - 1)
	var node := Kit.spawn(pieces[pick])
	prop.add_child(node)
	node.rotation.y = rng.randf_range(-0.4, 0.4)
	return sizes[pick]


## Les bureaux sont contre le mur du haut ou de gauche de leur salle :
## ils regardent vers l'intérieur.
static func _desk_facing(level: LevelGenerator, tile: Vector2i) -> Vector3:
	var room := level.room_at(tile)
	if room != null and tile.y == room.rect.position.y:
		return Vector3(0.0, 0.0, 1.0)
	return Vector3(1.0, 0.0, 0.0)


static func _add(prop: Node3D, piece: String, footprint: Vector3) -> Vector3:
	prop.add_child(Kit.spawn(piece))
	return footprint
