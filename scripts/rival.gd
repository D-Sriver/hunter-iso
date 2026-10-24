class_name Rival
extends CharacterBody3D
## Hunter rival piloté par l'IA. Il cherche la relique, et à chaque alerte il réagit selon sa
## personnalité.

enum Personality { TRACKER, SENTINEL, OPPORTUNIST }

const SEARCH_SPEED := 3.6
const HUNT_SPEED := 5.1
const REPATH_INTERVAL := 0.4
const ARRIVAL_DISTANCE := 0.35
const SIGHT_RANGE := 9.0
const RELIC_SIGHT_RANGE := 12.0
const CHASE_MEMORY := 3.0
const HIT_COOLDOWN := 1.2
const SENTINEL_ENGAGE_DISTANCE := 6.0
const OPPORTUNIST_DISTANCE := 7.0

var personality: Personality
var display_name: String
var color: Color

var _game: Main
var _speed := SEARCH_SPEED
var _path := PackedVector3Array()
var _path_index := 0
var _repath_timer := 0.0
var _stun_timer := 0.0
var _hit_cooldown := 0.0
var _chase_timer := 0.0
var _relic_known := false
var _has_noise := false
var _noise_position := Vector3.ZERO
var _has_wander_target := false
var _wander_target := Vector3.ZERO
var _status := ""
var _visual: Node3D
var _label: Label3D


func setup(game: Main, kind: Personality) -> void:
	_game = game
	personality = kind
	match kind:
		Personality.TRACKER:
			display_name = "le Traqueur"
			color = Color(1.0, 0.2, 0.25)
		Personality.SENTINEL:
			display_name = "la Sentinelle"
			color = Color(1.0, 0.55, 0.1)
		Personality.OPPORTUNIST:
			display_name = "l'Opportuniste"
			color = Color(0.95, 0.2, 0.7)


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = LevelBuilder.WALL_LAYER
	_build_body()


func _physics_process(delta: float) -> void:
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	if not _game.is_playing():
		return
	if _stun_timer > 0.0:
		_stun_timer -= delta
		_visual.rotation.z = 0.5
		_set_status("zZ")
		return
	_visual.rotation.z = 0.0
	_chase_timer = maxf(_chase_timer - delta, 0.0)
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = REPATH_INTERVAL
		_path = _game.find_path(global_position, _choose_goal())
		_path_index = 0
	_follow_path()
	if _game.relic_carrier == self and _game.is_on_exit(global_position):
		_game.on_rival_escaped(self)


func stun(duration: float) -> void:
	_stun_timer = duration
	velocity = Vector3.ZERO


func is_stunned() -> bool:
	return _stun_timer > 0.0


func can_hit() -> bool:
	return _hit_cooldown <= 0.0 and not is_stunned()


func on_hit_landed() -> void:
	_hit_cooldown = HIT_COOLDOWN


## Appelé par l'alerte générale : quelqu'un a pris, perdu ou fait tomber la relique.
func on_relic_alert() -> void:
	_relic_known = true
	_has_noise = false
	_repath_timer = 0.0


func hear_noise(origin: Vector3) -> void:
	if _game.relic_carrier != null:
		return
	_has_noise = true
	_noise_position = origin
	_repath_timer = 0.0


func _choose_goal() -> Vector3:
	var carrier := _game.relic_carrier
	if carrier == self:
		_set_mode("Fuite", HUNT_SPEED)
		return _game.nearest_exit(global_position)
	if carrier != null:
		return _goal_when_relic_carried(carrier)
	if _game.is_relic_on_ground():
		if (
			not _relic_known
			and _game.can_see(global_position, _game.relic.global_position, RELIC_SIGHT_RANGE)
		):
			_relic_known = true
		if _relic_known:
			_set_mode("Relique !", HUNT_SPEED)
			return _game.relic.global_position
	if personality != Personality.OPPORTUNIST and _sees_player():
		_chase_timer = CHASE_MEMORY
	if _chase_timer > 0.0:
		_set_mode("!", HUNT_SPEED)
		return _game.player.global_position
	if _has_noise:
		if _flat_distance(_noise_position) < 1.0:
			_has_noise = false
		else:
			_set_mode("?", SEARCH_SPEED)
			return _noise_position
	return _wander()


func _goal_when_relic_carried(carrier: Node3D) -> Vector3:
	var carrier_distance := _flat_distance(carrier.global_position)
	if personality == Personality.TRACKER:
		_set_mode("Traque", HUNT_SPEED)
		return carrier.global_position
	if personality == Personality.SENTINEL:
		if carrier_distance < SENTINEL_ENGAGE_DISTANCE:
			_set_mode("!", HUNT_SPEED)
			return carrier.global_position
		_set_mode("Garde", HUNT_SPEED)
		return _game.nearest_exit(carrier.global_position)
	# L'Opportuniste suit de loin et ne frappe que quand le porteur est affaibli.
	var carrier_is_weak := carrier == _game.player and _game.player.health <= 1
	if carrier_is_weak:
		_set_mode("!", HUNT_SPEED)
		return carrier.global_position
	_set_mode("Guette", SEARCH_SPEED)
	if carrier_distance < OPPORTUNIST_DISTANCE:
		return global_position
	return carrier.global_position


func _wander() -> Vector3:
	if not _has_wander_target or _flat_distance(_wander_target) < 1.0:
		_wander_target = _game.random_floor_position()
		_has_wander_target = true
	_set_mode("...", SEARCH_SPEED)
	return _wander_target


func _sees_player() -> bool:
	var player := _game.player
	if player.is_dead:
		return false
	return _game.can_see(global_position, player.global_position, SIGHT_RANGE)


func _follow_path() -> void:
	while _path_index < _path.size() and _flat_distance(_path[_path_index]) < ARRIVAL_DISTANCE:
		_path_index += 1
	if _path_index >= _path.size():
		velocity = Vector3.ZERO
		return
	var to_target := _path[_path_index] - global_position
	to_target.y = 0.0
	velocity = to_target.normalized() * _speed
	move_and_slide()
	position.y = 0.0
	rotation.y = atan2(velocity.x, velocity.z)


func _set_mode(status: String, speed: float) -> void:
	_speed = speed
	_set_status(status)


func _set_status(status: String) -> void:
	if status == _status:
		return
	_status = status
	_label.text = "%s\n%s" % [display_name, status]


func _flat_distance(target: Vector3) -> float:
	return Vector2(global_position.x - target.x, global_position.z - target.z).length()


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.85
	add_child(collider)

	_visual = Node3D.new()
	add_child(_visual)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	capsule.material = Materials.neon(color, 0.5)
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.position.y = 0.85
	_visual.add_child(body)

	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.5, 0.14, 0.2)
	visor_mesh.material = Materials.neon(Color(1.0, 0.9, 0.3), 2.5)
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 1.35, 0.32)
	_visual.add_child(visor)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 36
	_label.outline_size = 8
	_label.pixel_size = 0.01
	_label.modulate = color
	_label.position.y = 2.4
	add_child(_label)
	_set_status("...")
