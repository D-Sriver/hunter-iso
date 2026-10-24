class_name LevelGenerator
extends RefCounted
## Génère un niveau en salles : une salle par emplacement d'une grille, reliées par des couloirs
## courts. Chaque salle reçoit un rôle (départ, chambre forte, serveurs...) et son mobilier.

enum Tile { WALL, FLOOR, FURNITURE }
enum RoomKind { START, VAULT, SERVER, LAB, STORAGE, OFFICE }

const DIRECTIONS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const NEIGHBORS_8 := [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]
const SLOT_SIZE := 10
const ROOM_MIN := 5
const ROOM_MAX := 8
const EXTRA_LINK_CHANCE := 0.3
const EXTRA_EXIT_COUNT := 2
const STORAGE_CRATE_CHANCE := 0.3
const OFFICE_DESK_CHANCE := 0.6
const FILLER_KINDS := [RoomKind.SERVER, RoomKind.LAB, RoomKind.STORAGE, RoomKind.OFFICE]


class Room:
	var rect: Rect2i
	var slot: Vector2i
	var kind := 0

	func center() -> Vector2i:
		return rect.position + rect.size / 2

	func contains(tile: Vector2i) -> bool:
		return rect.has_point(tile)


var width: int
var height: int
var rooms: Array[Room] = []
var start_tile: Vector2i
var relic_tile: Vector2i
var exit_tiles: Array[Vector2i] = []
var floor_tiles: Array[Vector2i] = []
var chest_spots: Array[Vector2i] = []
## Mobilier par tuile : "rack", "pillar", "table", "crates" ou "desk".
var furniture := {}

var _slots: Vector2i
var _floor_count := 0
var _tiles := PackedByteArray()
var _room_ids := PackedInt32Array()
var _rng := RandomNumberGenerator.new()


func _init(slots: Vector2i, seed_value: int) -> void:
	_slots = slots
	width = slots.x * SLOT_SIZE + 1
	height = slots.y * SLOT_SIZE + 1
	_rng.seed = seed_value
	_tiles.resize(width * height)
	_tiles.fill(Tile.WALL)
	_room_ids.resize(width * height)
	_room_ids.fill(-1)


func generate() -> void:
	_place_rooms()
	_link_rooms()
	_assign_kinds()
	_place_exits()
	_furnish_rooms()
	_collect_floor_tiles()
	_collect_chest_spots()


func is_floor(tile: Vector2i) -> bool:
	return _tile_at(tile) == Tile.FLOOR


## Sol ou mobilier : tout ce qui n'est pas un mur reçoit une dalle.
func is_ground(tile: Vector2i) -> bool:
	return _in_bounds(tile) and _tile_at(tile) != Tile.WALL


func room_at(tile: Vector2i) -> Room:
	if not _in_bounds(tile):
		return null
	var index := _room_ids[_index(tile)]
	return rooms[index] if index >= 0 else null


func ground_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			if is_ground(Vector2i(x, y)):
				result.append(Vector2i(x, y))
	return result


## Distance en nombre de tuiles depuis `origin`, par parcours en largeur.
func distances_from(origin: Vector2i) -> Dictionary:
	var distances := {origin: 0}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		var tile_distance: int = distances[tile]
		for dir in DIRECTIONS:
			var next: Vector2i = tile + dir
			if is_floor(next) and not distances.has(next):
				distances[next] = tile_distance + 1
				queue.append(next)
	return distances


## Murs visibles : toute tuile de mur qui touche du sol ou du mobilier.
func wall_tiles_touching_floor() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(-1, height + 1):
		for x in range(-1, width + 1):
			var tile := Vector2i(x, y)
			if is_ground(tile):
				continue
			for offset in NEIGHBORS_8:
				if is_ground(tile + offset):
					result.append(tile)
					break
	return result


func _place_rooms() -> void:
	for slot_y in _slots.y:
		for slot_x in _slots.x:
			var size := Vector2i(
				_rng.randi_range(ROOM_MIN, ROOM_MAX), _rng.randi_range(ROOM_MIN, ROOM_MAX)
			)
			# La première ligne et la première colonne de chaque emplacement restent des murs :
			# deux salles voisines ne se touchent jamais.
			var origin := Vector2i(
				slot_x * SLOT_SIZE + 1 + _rng.randi_range(0, SLOT_SIZE - 1 - size.x),
				slot_y * SLOT_SIZE + 1 + _rng.randi_range(0, SLOT_SIZE - 1 - size.y)
			)
			var room := Room.new()
			room.rect = Rect2i(origin, size)
			room.slot = Vector2i(slot_x, slot_y)
			rooms.append(room)
			for y in range(room.rect.position.y, room.rect.end.y):
				for x in range(room.rect.position.x, room.rect.end.x):
					_set_tile(Vector2i(x, y), Tile.FLOOR)
					_room_ids[_index(Vector2i(x, y))] = rooms.size() - 1


## Arbre couvrant sur la grille des emplacements,
## plus quelques liens en trop pour créer des boucles.
func _link_rooms() -> void:
	var visited := {Vector2i.ZERO: true}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for dir in DIRECTIONS:
			var next: Vector2i = current + dir
			if _is_slot(next) and not visited.has(next):
				options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var chosen: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
		_carve_corridor(_room_in_slot(current), _room_in_slot(chosen))
		visited[chosen] = true
		stack.append(chosen)

	for room in rooms:
		for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
			var neighbor_slot: Vector2i = room.slot + dir
			if _is_slot(neighbor_slot) and _rng.randf() < EXTRA_LINK_CHANCE:
				_carve_corridor(room, _room_in_slot(neighbor_slot))


## Couloir en L entre deux salles voisines. Le premier segment suit l'axe qui les sépare,
## pour que le couloir reste dans leurs deux emplacements.
func _carve_corridor(from_room: Room, to_room: Room) -> void:
	var from := from_room.center()
	var to := to_room.center()
	var corner := Vector2i(to.x, from.y)
	if from_room.slot.x == to_room.slot.x:
		corner = Vector2i(from.x, to.y)
	_carve_line(from, corner)
	_carve_line(corner, to)


func _carve_line(from: Vector2i, to: Vector2i) -> void:
	var step := (to - from).sign()
	var tile := from
	while true:
		if _tile_at(tile) == Tile.WALL:
			_set_tile(tile, Tile.FLOOR)
		if tile == to:
			break
		tile += step


func _assign_kinds() -> void:
	var start_room := rooms[0]
	start_room.kind = RoomKind.START
	start_tile = start_room.center()

	var distances := distances_from(start_tile)
	var vault := start_room
	var best_distance := -1
	for room in rooms:
		var room_distance: int = distances.get(room.center(), -1)
		if room_distance > best_distance:
			best_distance = room_distance
			vault = room
	vault.kind = RoomKind.VAULT
	relic_tile = vault.center()

	var fillers := FILLER_KINDS.duplicate()
	fillers.shuffle()
	var next_filler := 0
	for room in rooms:
		if room == start_room or room == vault:
			continue
		room.kind = fillers[next_filler % fillers.size()]
		next_filler += 1


## Une sortie dans la salle de départ, deux autres dans des salles loin de la chambre forte.
## Chaque sortie est dans le coin du fond de sa salle, pour ne pas apparaître dessus.
func _place_exits() -> void:
	exit_tiles.clear()
	var candidates: Array[Room] = []
	var vault_slot := room_at(relic_tile).slot
	for room in rooms:
		if room.kind == RoomKind.START:
			exit_tiles.append(room.rect.position)
		elif room.kind != RoomKind.VAULT:
			var gap := absi(room.slot.x - vault_slot.x) + absi(room.slot.y - vault_slot.y)
			if gap >= 2:
				candidates.append(room)
	candidates.shuffle()
	for room in candidates.slice(0, EXTRA_EXIT_COUNT):
		exit_tiles.append(room.rect.position)


func _furnish_rooms() -> void:
	_floor_count = 0
	for value in _tiles:
		if value == Tile.FLOOR:
			_floor_count += 1
	for room in rooms:
		for spot in _furniture_layout(room):
			var tile: Vector2i = spot[0]
			if not _can_furnish(room, tile):
				continue
			_set_tile(tile, Tile.FURNITURE)
			_floor_count -= 1
			# Le mobilier ne doit jamais couper le niveau en deux : sinon on annule.
			if distances_from(start_tile).size() == _floor_count:
				furniture[tile] = spot[1]
			else:
				_set_tile(tile, Tile.FLOOR)
				_floor_count += 1


## Liste de [tuile, type de meuble] proposés pour une salle, selon son rôle.
func _furniture_layout(room: Room) -> Array:
	var layout := []
	var r := room.rect
	match room.kind:
		RoomKind.SERVER:
			# Rangées de baies serveur, une ligne sur deux : des allées où l'on se cache.
			for y in range(r.position.y + 1, r.end.y - 1, 2):
				for x in range(r.position.x + 1, r.end.x - 1):
					layout.append([Vector2i(x, y), "rack"])
		RoomKind.LAB:
			for y in range(r.position.y + 2, r.end.y - 2):
				for x in range(r.position.x + 2, r.end.x - 2):
					layout.append([Vector2i(x, y), "table"])
		RoomKind.STORAGE:
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					if _rng.randf() < STORAGE_CRATE_CHANCE:
						layout.append([Vector2i(x, y), "crates"])
		RoomKind.OFFICE:
			# Bureaux contre les murs du fond, ceux que la caméra voit.
			for x in range(r.position.x + 1, r.end.x):
				if _rng.randf() < OFFICE_DESK_CHANCE:
					layout.append([Vector2i(x, r.position.y), "desk"])
			for y in range(r.position.y + 1, r.end.y):
				if _rng.randf() < OFFICE_DESK_CHANCE:
					layout.append([Vector2i(r.position.x, y), "desk"])
		RoomKind.VAULT:
			for corner in [
				Vector2i(r.position.x + 1, r.position.y + 1),
				Vector2i(r.end.x - 2, r.position.y + 1),
				Vector2i(r.position.x + 1, r.end.y - 2),
				Vector2i(r.end.x - 2, r.end.y - 2),
			]:
				layout.append([corner, "pillar"])
	return layout


func _can_furnish(room: Room, tile: Vector2i) -> bool:
	if not room.contains(tile) or not is_floor(tile):
		return false
	if tile == room.center() or exit_tiles.has(tile):
		return false
	# Jamais devant une entrée : la tuile ne doit toucher aucun couloir.
	for dir in DIRECTIONS:
		var neighbor: Vector2i = tile + dir
		if is_floor(neighbor) and room_at(neighbor) == null:
			return false
	return true


func _collect_floor_tiles() -> void:
	floor_tiles.clear()
	for y in height:
		for x in width:
			if is_floor(Vector2i(x, y)):
				floor_tiles.append(Vector2i(x, y))


## Emplacements de coffres : contre un mur ou un meuble, dans les salles ordinaires.
func _collect_chest_spots() -> void:
	chest_spots.clear()
	for tile in floor_tiles:
		var room := room_at(tile)
		if room == null or room.kind == RoomKind.START or room.kind == RoomKind.VAULT:
			continue
		if exit_tiles.has(tile) or tile == room.center():
			continue
		var against_something := false
		var near_corridor := false
		for dir in DIRECTIONS:
			var neighbor: Vector2i = tile + dir
			if not is_floor(neighbor):
				against_something = true
			elif room_at(neighbor) == null:
				near_corridor = true
		if against_something and not near_corridor:
			chest_spots.append(tile)


func _room_in_slot(slot: Vector2i) -> Room:
	return rooms[slot.y * _slots.x + slot.x]


func _is_slot(slot: Vector2i) -> bool:
	return slot.x >= 0 and slot.y >= 0 and slot.x < _slots.x and slot.y < _slots.y


func _in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height


func _tile_at(tile: Vector2i) -> int:
	if not _in_bounds(tile):
		return Tile.WALL
	return _tiles[_index(tile)]


func _set_tile(tile: Vector2i, value: int) -> void:
	_tiles[_index(tile)] = value


func _index(tile: Vector2i) -> int:
	return tile.y * width + tile.x
