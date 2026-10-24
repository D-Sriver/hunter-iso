class_name Main
extends Node3D
## Orchestre une run : génère le labyrinthe, place les acteurs, gère la relique, les coffres,
## l'alerte et la fin de run.

enum RunState { PLAYING, WON, LOST }

const TILE_SIZE := 2.0
const MAZE_CELLS := Vector2i(11, 11)
const LOOP_CHANCE := 0.12
const ROOM_COUNT := 3
const CHEST_COUNT := 6
const CHEST_LOOT_MIN := 20
const CHEST_LOOT_MAX := 60
const CHEST_OPEN_TIME := 1.5
const RELIC_VALUE := 150
const RELIC_HEIGHT := 0.9
const PICKUP_RANGE := 1.0
const INTERACT_RANGE := 1.6
const CONTACT_RANGE := 1.1
const EXIT_RANGE := 1.0
const NOISE_RANGE := 14.0
const ATTACK_RANGE := 2.0
const ATTACK_STUN_TIME := 2.5
const STEAL_STUN_TIME := 1.5
const ALERT_DURATION := 3.5
const RIVAL_SPAWN_MIN_RATIO := 0.4
const CAMERA_OFFSET := Vector3(15.0, 15.0, 15.0)
const CAMERA_SIZE := 22.0
const CAMERA_FOLLOW_SPEED := 6.0
const RELIC_COLOR := Color(0.3, 1.0, 1.0)
const BEACON_COLOR := Color(1.0, 0.25, 0.35)

var maze: MazeGenerator
var player: Player
var rivals: Array[Rival] = []
var relic: Node3D
## Celui qui porte la relique (joueur ou rival), null si elle est au sol ou perdue.
var relic_carrier: Node3D = null

var _astar := AStarGrid2D.new()
var _chests: Array[Chest] = []
var _relic_lost := false
var _beacon: MeshInstance3D
var _beacon_timer := 0.0
var _camera: Camera3D
var _camera_focus := Vector3.ZERO
var _hud: Hud
var _run_state := RunState.PLAYING
var _loot := 0
var _credits := 0
var _chest_progress := 0.0


func _ready() -> void:
	InputSetup.ensure_actions()
	maze = MazeGenerator.new(MAZE_CELLS.x, MAZE_CELLS.y, randi())
	maze.generate(LOOP_CHANCE, ROOM_COUNT)
	_setup_pathfinding()
	LevelBuilder.build(self, maze, TILE_SIZE)
	_setup_environment()
	_spawn_player()
	_spawn_relic()
	_spawn_chests()
	_spawn_rivals()
	_setup_camera()
	_hud = Hud.new()
	add_child(_hud)
	_credits = SaveData.load_credits()
	_hud.show_alert("Trouve la relique avant les autres hunters", 4.0)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"restart"):
		get_tree().reload_current_scene()
		return
	_update_camera(delta)
	_update_beacon(delta)
	relic.rotate_y(delta * 2.0)


func _physics_process(delta: float) -> void:
	if _run_state != RunState.PLAYING:
		return
	_update_relic()
	_check_rival_contacts()
	var hint := _update_chests(delta)
	if hint.is_empty():
		hint = _update_exits()
	_hud.set_hint(hint)
	_hud.set_stats(player.health, Player.MAX_HEALTH, _loot, _credits, relic_carrier == player)


# --- Requêtes utilisées par les rivaux ---


func is_playing() -> bool:
	return _run_state == RunState.PLAYING


func is_relic_on_ground() -> bool:
	return relic_carrier == null and not _relic_lost


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := _walkable_tile_near(world_to_tile(from))
	var goal := _walkable_tile_near(world_to_tile(to))
	var result := PackedVector3Array()
	for tile in _astar.get_id_path(start, goal):
		result.append(tile_to_world(tile))
	# La première tuile est celle où l'on se trouve déjà : la viser ferait reculer.
	if result.size() > 1:
		result.remove_at(0)
	return result


func can_see(from: Vector3, to: Vector3, max_range: float) -> bool:
	if flat_distance(from, to) > max_range:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP, to + Vector3.UP, LevelBuilder.WALL_LAYER
	)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func nearest_exit(from: Vector3) -> Vector3:
	var best := tile_to_world(maze.exit_tiles[0])
	for tile in maze.exit_tiles:
		var exit_position := tile_to_world(tile)
		if flat_distance(from, exit_position) < flat_distance(from, best):
			best = exit_position
	return best


func is_on_exit(position_to_check: Vector3) -> bool:
	return flat_distance(position_to_check, nearest_exit(position_to_check)) < EXIT_RANGE


func random_floor_position() -> Vector3:
	return tile_to_world(maze.floor_tiles.pick_random())


func on_rival_escaped(rival: Rival) -> void:
	relic_carrier = null
	_relic_lost = true
	relic.visible = false
	_hud.show_alert(
		(
			"%s s'est enfui avec la relique ! Sauve ton butin : trouve une sortie."
			% _capitalized(rival.display_name)
		),
		5.0
	)
	for other in rivals:
		other.on_relic_alert()


# --- Conversions grille / monde ---


func tile_to_world(tile: Vector2i) -> Vector3:
	return Vector3(tile.x * TILE_SIZE, 0.0, tile.y * TILE_SIZE)


func world_to_tile(world_position: Vector3) -> Vector2i:
	return Vector2i(roundi(world_position.x / TILE_SIZE), roundi(world_position.z / TILE_SIZE))


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Relique et alerte ---


func _update_relic() -> void:
	if relic_carrier != null:
		relic.global_position = relic_carrier.global_position + Vector3(0.0, 2.3, 0.0)
		return
	if _relic_lost:
		return
	if (
		flat_distance(player.global_position, relic.global_position) < PICKUP_RANGE
		and not player.is_dead
	):
		_give_relic(player)
		return
	for rival in rivals:
		if (
			not rival.is_stunned()
			and flat_distance(rival.global_position, relic.global_position) < PICKUP_RANGE
		):
			_give_relic(rival)
			return


func _give_relic(carrier: Node3D) -> void:
	relic_carrier = carrier
	player.is_carrying = carrier == player
	if carrier == player:
		_announce("ALERTE : tu as la relique ! Tous les hunters savent où tu es.")
	else:
		_announce("ALERTE : %s a pris la relique !" % (carrier as Rival).display_name)


func _drop_relic(at: Vector3) -> void:
	relic_carrier = null
	player.is_carrying = false
	relic.global_position = Vector3(at.x, RELIC_HEIGHT, at.z)
	_announce("La relique est tombée ! Tout le monde fonce dessus.")


## L'alerte générale prévient tout le monde et révèle brièvement la relique d'un faisceau visible
## de partout.
func _announce(text: String) -> void:
	_hud.show_alert(text, ALERT_DURATION)
	_beacon_timer = ALERT_DURATION
	for rival in rivals:
		rival.on_relic_alert()


func _update_beacon(delta: float) -> void:
	_beacon_timer = maxf(_beacon_timer - delta, 0.0)
	_beacon.visible = _beacon_timer > 0.0 and relic.visible
	_beacon.global_position = Vector3(relic.global_position.x, 0.0, relic.global_position.z)


# --- Combat et contacts ---


func _on_player_attacked(origin: Vector3, facing: Vector3) -> void:
	for rival in rivals:
		var to_rival := rival.global_position - origin
		to_rival.y = 0.0
		if to_rival.length() > ATTACK_RANGE or facing.dot(to_rival.normalized()) < 0.3:
			continue
		rival.stun(ATTACK_STUN_TIME)
		if relic_carrier == rival:
			_drop_relic(rival.global_position)


func _check_rival_contacts() -> void:
	for rival in rivals:
		if not rival.can_hit():
			continue
		# Un rival qui rattrape un autre rival porteur le bouscule et la relique tombe.
		if relic_carrier is Rival and relic_carrier != rival:
			var carrier := relic_carrier as Rival
			if flat_distance(rival.global_position, carrier.global_position) < CONTACT_RANGE:
				rival.on_hit_landed()
				carrier.stun(STEAL_STUN_TIME)
				_drop_relic(carrier.global_position)
				continue
		if flat_distance(rival.global_position, player.global_position) > CONTACT_RANGE:
			continue
		rival.on_hit_landed()
		if not player.take_hit():
			continue
		if player.is_dead:
			_end_run(false, "Tu es mort.\nLe butin de cette run est perdu.")
			return
		if relic_carrier == player:
			relic_carrier = rival
			player.is_carrying = false
			_announce("ALERTE : %s t'a volé la relique !" % rival.display_name)


# --- Coffres et sorties ---


## Retourne la consigne à afficher près d'un coffre, ou une chaîne vide.
func _update_chests(delta: float) -> String:
	var nearby: Chest = null
	for chest in _chests:
		if (
			not chest.opened
			and flat_distance(chest.global_position, player.global_position) < INTERACT_RANGE
		):
			nearby = chest
			break
	if nearby == null:
		_chest_progress = 0.0
		return ""
	if not Input.is_action_pressed(&"interact"):
		_chest_progress = 0.0
		return "Maintiens E pour ouvrir le coffre (ça fait du bruit)"
	_chest_progress += delta / CHEST_OPEN_TIME
	if _chest_progress < 1.0:
		return "Ouverture... %d %%" % roundi(_chest_progress * 100.0)
	_chest_progress = 0.0
	var value := nearby.open()
	_loot += value
	_hud.show_alert("+%d ¢ de butin. Le bruit a attiré du monde..." % value, 2.5)
	for rival in rivals:
		if flat_distance(rival.global_position, nearby.global_position) < NOISE_RANGE:
			rival.hear_noise(nearby.global_position)
	return ""


func _update_exits() -> String:
	if not is_on_exit(player.global_position):
		return ""
	if relic_carrier == player:
		_end_run(true, "Relique ramenée !")
		return ""
	if Input.is_action_just_pressed(&"interact"):
		_end_run(true, "Tu t'es échappé sans la relique.")
		return ""
	return "E : t'échapper maintenant avec ton butin (sans la relique)"


func _end_run(escaped: bool, title: String) -> void:
	_run_state = RunState.WON if escaped else RunState.LOST
	var gained := 0
	if escaped:
		gained = _loot + (RELIC_VALUE if relic_carrier == player else 0)
	_credits = SaveData.add_credits(gained)
	_hud.set_stats(player.health, Player.MAX_HEALTH, _loot, _credits, relic_carrier == player)
	_hud.show_end(
		"%s\n+%d ¢   (total : %d ¢)\n\nR pour une nouvelle run" % [title, gained, _credits]
	)
	player.set_physics_process(false)


# --- Mise en place ---


func _setup_pathfinding() -> void:
	_astar.region = Rect2i(0, 0, maze.width, maze.height)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	for y in maze.height:
		for x in maze.width:
			var tile := Vector2i(x, y)
			if not maze.is_floor(tile):
				_astar.set_point_solid(tile)


func _walkable_tile_near(tile: Vector2i) -> Vector2i:
	var clamped := Vector2i(clampi(tile.x, 0, maze.width - 1), clampi(tile.y, 0, maze.height - 1))
	if maze.is_floor(clamped):
		return clamped
	for offset in MazeGenerator.NEIGHBORS_8:
		var neighbor: Vector2i = clamped + offset
		if maze.is_floor(neighbor):
			return neighbor
	return maze.start_tile


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.01, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.35, 0.7)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.05
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	moon.light_color = Color(0.7, 0.75, 1.0)
	moon.light_energy = 0.5
	moon.shadow_enabled = true
	add_child(moon)


func _spawn_player() -> void:
	player = Player.new()
	add_child(player)
	player.global_position = tile_to_world(maze.start_tile)
	player.attacked.connect(_on_player_attacked)


func _spawn_relic() -> void:
	relic = Node3D.new()
	add_child(relic)
	relic.global_position = tile_to_world(maze.relic_tile) + Vector3(0.0, RELIC_HEIGHT, 0.0)

	var gem := SphereMesh.new()
	gem.radius = 0.35
	gem.height = 0.9
	gem.radial_segments = 4
	gem.rings = 1
	gem.material = Materials.neon(RELIC_COLOR, 3.0)
	var gem_instance := MeshInstance3D.new()
	gem_instance.mesh = gem
	relic.add_child(gem_instance)

	var light := OmniLight3D.new()
	light.light_color = RELIC_COLOR
	light.light_energy = 2.0
	light.omni_range = 4.0
	relic.add_child(light)

	var beam := CylinderMesh.new()
	beam.top_radius = 0.25
	beam.bottom_radius = 0.25
	beam.height = 30.0
	beam.material = Materials.neon(BEACON_COLOR, 3.0)
	_beacon = MeshInstance3D.new()
	_beacon.mesh = beam
	_beacon.visible = false
	add_child(_beacon)


func _spawn_chests() -> void:
	var excluded: Array[Vector2i] = [maze.start_tile, maze.relic_tile]
	excluded.append_array(maze.exit_tiles)
	var spots := maze.dead_end_tiles().filter(
		func(tile: Vector2i) -> bool: return not excluded.has(tile)
	)
	spots.shuffle()
	for tile in spots.slice(0, CHEST_COUNT):
		var chest := Chest.new()
		chest.setup(randi_range(CHEST_LOOT_MIN, CHEST_LOOT_MAX))
		add_child(chest)
		chest.global_position = tile_to_world(tile)
		_chests.append(chest)


func _spawn_rivals() -> void:
	var distances := maze.distances_from(maze.start_tile)
	var max_distance: int = distances[maze.relic_tile]
	var spots: Array[Vector2i] = []
	for tile in maze.floor_tiles:
		var tile_distance: int = distances.get(tile, 0)
		if tile_distance >= max_distance * RIVAL_SPAWN_MIN_RATIO and tile != maze.relic_tile:
			spots.append(tile)
	spots.shuffle()
	var kinds := [
		Rival.Personality.TRACKER, Rival.Personality.SENTINEL, Rival.Personality.OPPORTUNIST
	]
	for i in kinds.size():
		var rival := Rival.new()
		rival.setup(self, kinds[i])
		add_child(rival)
		rival.global_position = tile_to_world(spots[i % spots.size()])
		rivals.append(rival)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.far = 200.0
	add_child(_camera)
	_camera_focus = player.global_position
	_place_camera()


func _update_camera(delta: float) -> void:
	_camera_focus = _camera_focus.lerp(
		player.global_position, minf(delta * CAMERA_FOLLOW_SPEED, 1.0)
	)
	_place_camera()


func _place_camera() -> void:
	_camera.global_position = _camera_focus + CAMERA_OFFSET
	_camera.look_at(_camera_focus, Vector3.UP)


func _capitalized(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)
