class_name MazeGenerator
extends RefCounted
## Génère un labyrinthe sur grille de tuiles.
## Chaque cellule logique occupe une tuile impaire, les murs entre cellules occupent les tuiles
## paires.

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
const EXIT_COUNT := 3

var width: int
var height: int
var start_tile: Vector2i
var relic_tile: Vector2i
var exit_tiles: Array[Vector2i] = []
var floor_tiles: Array[Vector2i] = []

var _cells_w: int
var _cells_h: int
var _floor := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func _init(cells_w: int, cells_h: int, seed_value: int) -> void:
	_cells_w = cells_w
	_cells_h = cells_h
	width = cells_w * 2 + 1
	height = cells_h * 2 + 1
	_rng.seed = seed_value
	_floor.resize(width * height)
	_floor.fill(0)


func generate(loop_chance: float, room_count: int) -> void:
	_carve_corridors()
	_open_loops(loop_chance)
	_carve_rooms(room_count)
	start_tile = cell_to_tile(Vector2i.ZERO)
	_collect_floor_tiles()
	relic_tile = _farthest_tile_from(start_tile)
	_open_exits()
	_collect_floor_tiles()


func is_floor(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= width or tile.y >= height:
		return false
	return _floor[tile.y * width + tile.x] == 1


func cell_to_tile(cell: Vector2i) -> Vector2i:
	return cell * 2 + Vector2i.ONE


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


func dead_end_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for tile in floor_tiles:
		var open_sides := 0
		for dir in DIRECTIONS:
			if is_floor(tile + dir):
				open_sides += 1
		if open_sides == 1:
			result.append(tile)
	return result


## Murs visibles : toute tuile pleine qui touche du sol, y compris juste derrière les sorties.
func wall_tiles_touching_floor() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(-1, height + 1):
		for x in range(-1, width + 1):
			var tile := Vector2i(x, y)
			if is_floor(tile):
				continue
			for offset in NEIGHBORS_8:
				if is_floor(tile + offset):
					result.append(tile)
					break
	return result


func _carve_corridors() -> void:
	var visited := {Vector2i.ZERO: true}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	_open(cell_to_tile(Vector2i.ZERO))
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for dir in DIRECTIONS:
			var next: Vector2i = current + dir
			if _is_cell_in_bounds(next) and not visited.has(next):
				options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var chosen: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
		_open(cell_to_tile(current) + (chosen - current))
		_open(cell_to_tile(chosen))
		visited[chosen] = true
		stack.append(chosen)


## Casse quelques murs pour créer des boucles : sans elles, une poursuite se finit toujours en
## cul-de-sac.
func _open_loops(loop_chance: float) -> void:
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var tile := Vector2i(x, y)
			if is_floor(tile):
				continue
			var links_vertical := (
				is_floor(tile + Vector2i(0, -1)) and is_floor(tile + Vector2i(0, 1))
			)
			var links_horizontal := (
				is_floor(tile + Vector2i(-1, 0)) and is_floor(tile + Vector2i(1, 0))
			)
			if (links_vertical or links_horizontal) and _rng.randf() < loop_chance:
				_open(tile)


func _carve_rooms(room_count: int) -> void:
	for i in room_count:
		var cell := Vector2i(_rng.randi_range(1, _cells_w - 2), _rng.randi_range(1, _cells_h - 2))
		var center := cell_to_tile(cell)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_open(center + Vector2i(dx, dy))


func _open_exits() -> void:
	var candidates: Array[Vector2i] = []
	for side in [
		_top_exit_options(), _bottom_exit_options(), _left_exit_options(), _right_exit_options()
	]:
		var options: Array[Vector2i] = side
		if not options.is_empty():
			candidates.append(options[_rng.randi_range(0, options.size() - 1)])
	# Les sorties les plus éloignées du départ d'abord : on écarte celle qui rendrait la fuite
	# trop facile.
	candidates.sort_custom(_is_farther_from_start)
	exit_tiles.clear()
	for tile in candidates.slice(0, EXIT_COUNT):
		_open(tile)
		exit_tiles.append(tile)


func _top_exit_options() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(1, width - 1):
		if is_floor(Vector2i(x, 1)):
			result.append(Vector2i(x, 0))
	return result


func _bottom_exit_options() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(1, width - 1):
		if is_floor(Vector2i(x, height - 2)):
			result.append(Vector2i(x, height - 1))
	return result


func _left_exit_options() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(1, height - 1):
		if is_floor(Vector2i(1, y)):
			result.append(Vector2i(0, y))
	return result


func _right_exit_options() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(1, height - 1):
		if is_floor(Vector2i(width - 2, y)):
			result.append(Vector2i(width - 1, y))
	return result


func _farthest_tile_from(origin: Vector2i) -> Vector2i:
	var distances := distances_from(origin)
	var best := origin
	var best_distance := -1
	for tile in distances:
		var tile_distance: int = distances[tile]
		if tile_distance > best_distance:
			best_distance = tile_distance
			best = tile
	return best


func _collect_floor_tiles() -> void:
	floor_tiles.clear()
	for y in height:
		for x in width:
			var tile := Vector2i(x, y)
			if is_floor(tile):
				floor_tiles.append(tile)


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _cells_w and cell.y < _cells_h


func _open(tile: Vector2i) -> void:
	_floor[tile.y * width + tile.x] = 1


func _is_farther_from_start(a: Vector2i, b: Vector2i) -> bool:
	return _manhattan(a, start_tile) > _manhattan(b, start_tile)


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
