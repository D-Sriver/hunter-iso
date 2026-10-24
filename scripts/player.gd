class_name Player
extends CharacterBody3D
## Le hunter du joueur : déplacement isométrique, dash, attaque qui étourdit.

signal attacked(origin: Vector3, facing: Vector3)

const SPEED := 6.0
const CARRY_SPEED_FACTOR := 0.85
const DASH_SPEED := 17.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 0.8
const ATTACK_COOLDOWN := 0.45
const SLASH_TIME := 0.12
const MAX_HEALTH := 3
const INVULNERABLE_TIME := 1.2
## La caméra regarde le labyrinthe en diagonale : on tourne l'entrée de 45° pour que « haut »
## parte vers le haut de l'écran.
const ISO_YAW := PI / 4.0
const BODY_COLOR := Color(0.15, 0.9, 1.0)

var health := MAX_HEALTH
var is_dead := false
var is_carrying := false
var facing := Vector3(0, 0, 1)

var _dash_timer := 0.0
var _dash_cooldown := 0.0
var _dash_direction := Vector3.ZERO
var _attack_cooldown := 0.0
var _slash_timer := 0.0
var _invulnerable_timer := 0.0
var _visual: Node3D
var _slash: MeshInstance3D


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = LevelBuilder.WALL_LAYER
	_build_body()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_tick_timers(delta)

	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, ISO_YAW)
	if direction.length_squared() > 0.01:
		facing = direction.normalized()

	if Input.is_action_just_pressed(&"dash") and _dash_cooldown <= 0.0:
		_dash_timer = DASH_TIME
		_dash_cooldown = DASH_COOLDOWN
		_dash_direction = facing

	if Input.is_action_just_pressed(&"attack") and _attack_cooldown <= 0.0:
		_attack()

	if _dash_timer > 0.0:
		velocity = _dash_direction * DASH_SPEED
	else:
		var speed := SPEED * (CARRY_SPEED_FACTOR if is_carrying else 1.0)
		velocity = direction * speed
	move_and_slide()
	position.y = 0.0
	rotation.y = atan2(facing.x, facing.z)


## Retourne true si le coup porte. Le dash et l'invulnérabilité après un coup protègent.
func take_hit() -> bool:
	if is_dead or _dash_timer > 0.0 or _invulnerable_timer > 0.0:
		return false
	health -= 1
	_invulnerable_timer = INVULNERABLE_TIME
	if health <= 0:
		is_dead = true
		_visual.rotation.x = PI / 2.0
		_visual.position.y = 0.3
	return true


func _attack() -> void:
	_attack_cooldown = ATTACK_COOLDOWN
	_slash_timer = SLASH_TIME
	_slash.visible = true
	attacked.emit(global_position, facing)


func _tick_timers(delta: float) -> void:
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_invulnerable_timer = maxf(_invulnerable_timer - delta, 0.0)
	_slash_timer = maxf(_slash_timer - delta, 0.0)
	_slash.visible = _slash_timer > 0.0
	# Clignote pendant l'invulnérabilité pour que le joueur comprenne qu'il a été touché.
	_visual.visible = _invulnerable_timer <= 0.0 or fmod(_invulnerable_timer, 0.2) > 0.1


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
	capsule.material = Materials.neon(BODY_COLOR, 0.6)
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.position.y = 0.85
	_visual.add_child(body)

	# Visière : indique la direction du regard.
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.5, 0.14, 0.2)
	visor_mesh.material = Materials.neon(Color(1.0, 1.0, 1.0), 2.5)
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 1.35, 0.32)
	_visual.add_child(visor)

	var slash_mesh := BoxMesh.new()
	slash_mesh.size = Vector3(1.8, 0.08, 0.5)
	slash_mesh.material = Materials.neon(BODY_COLOR, 4.0)
	_slash = MeshInstance3D.new()
	_slash.mesh = slash_mesh
	_slash.position = Vector3(0.0, 0.9, 1.0)
	_slash.visible = false
	add_child(_slash)

	var light := OmniLight3D.new()
	light.light_color = BODY_COLOR
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.position.y = 2.0
	add_child(light)
