class_name Player
extends CharacterBody3D
## Le hunter du joueur : déplacement isométrique, dash, attaque qui étourdit.
## On vise à la souris (ou au stick droit) : le hunter regarde là où l'on vise, son cône de
## vision et ses coups suivent. Sans visée, il regarde là où il marche.

signal attacked(origin: Vector3, facing: Vector3)

enum Aim { MOVE, MOUSE, STICK }

const SPEED := 6.0
const CARRY_SPEED_FACTOR := 0.85
const DASH_SPEED := 17.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 0.8
const ATTACK_COOLDOWN := 0.45
const SLASH_TIME := 0.12
const MAX_HEALTH := 3
const INVULNERABLE_TIME := 1.2
## La caméra regarde le niveau en diagonale : on tourne l'entrée de 45° pour que « haut »
## parte vers le haut de l'écran.
const ISO_YAW := PI / 4.0
const BODY_COLOR := Color(0.15, 0.9, 1.0)
const MODEL := "hunter_kaz"
## En dessous de cette distance entre la souris et le hunter, on garde la direction actuelle.
const MIN_AIM_DISTANCE := 0.4

var max_health := MAX_HEALTH + Implants.bonus_health()
var health := max_health
var is_dead := false
var is_carrying := false
var facing := Vector3(0, 0, 1)
var aim_mode := Aim.MOVE

var _dash_timer := 0.0
var _dash_cooldown := 0.0
var _dash_direction := Vector3.ZERO
var _attack_cooldown := 0.0
var _slash_timer := 0.0
var _invulnerable_timer := 0.0
var _visual: Node3D
var _slash: MeshInstance3D
var _animator: HunterAnimator


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
	var aim := _aim_direction()
	if aim != Vector3.ZERO:
		facing = aim
	elif direction.length_squared() > 0.01:
		facing = direction.normalized()

	if Input.is_action_just_pressed(&"dash") and _dash_cooldown <= 0.0:
		_dash_timer = DASH_TIME
		_dash_cooldown = DASH_COOLDOWN * Implants.dash_cooldown_factor()
		# On dashe là où l'on court, même en visant ailleurs.
		_dash_direction = direction.normalized() if direction.length_squared() > 0.01 else facing
		_animator.trigger(&"dash")

	if Input.is_action_just_pressed(&"attack") and _attack_cooldown <= 0.0:
		_attack()

	if _dash_timer > 0.0:
		velocity = _dash_direction * DASH_SPEED
	else:
		var speed := SPEED * Implants.speed_factor() * (CARRY_SPEED_FACTOR if is_carrying else 1.0)
		velocity = direction * speed
	move_and_slide()
	position.y = 0.0
	rotation.y = atan2(facing.x, facing.z)
	_animator.update(delta, Vector2(velocity.x, velocity.z).length())


## La souris prend la main dès qu'elle bouge, le stick droit dès qu'on le pousse ; le reste de
## la manette rend la visée à la marche.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aim_mode = Aim.MOUSE
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var is_right_stick := motion.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
		if is_right_stick and absf(motion.axis_value) > InputSetup.DEADZONE:
			aim_mode = Aim.STICK
		elif not is_right_stick and aim_mode == Aim.MOUSE:
			aim_mode = Aim.MOVE
	elif event is InputEventJoypadButton and aim_mode == Aim.MOUSE:
		aim_mode = Aim.MOVE


## Vrai si le joueur vise en ce moment (la caméra se décale alors vers la visée).
func is_aiming() -> bool:
	return aim_mode != Aim.MOVE and is_physics_processing() and not is_dead


## Fige le hunter (dialogue, boutique) ou lui rend la main.
func set_controls_enabled(enabled: bool) -> void:
	set_physics_process(enabled)
	if not enabled:
		velocity = Vector3.ZERO
		_animator.update(0.0, 0.0)


## Retourne true si le coup porte. Le dash et l'invulnérabilité après un coup protègent.
func take_hit() -> bool:
	if is_dead or _dash_timer > 0.0 or _invulnerable_timer > 0.0:
		return false
	health -= 1
	_invulnerable_timer = INVULNERABLE_TIME
	if health <= 0:
		is_dead = true
		_animator.freeze()
		_visual.rotation.x = PI / 2.0
		_visual.position.y = 0.3
	return true


## Direction visée, à plat ; zéro si l'on ne vise pas (ou si la souris est sur le hunter).
func _aim_direction() -> Vector3:
	var aim := Vector3.ZERO
	match aim_mode:
		Aim.MOUSE:
			var camera := get_viewport().get_camera_3d() as IsoCamera
			if camera != null:
				aim = camera.mouse_ground_point() - global_position
				aim.y = 0.0
				if aim.length() < MIN_AIM_DISTANCE:
					return Vector3.ZERO
		Aim.STICK:
			var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
			aim = Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, ISO_YAW)
			if aim.length_squared() < 0.01:
				return Vector3.ZERO
	return aim.normalized()


func _attack() -> void:
	_attack_cooldown = ATTACK_COOLDOWN
	_slash_timer = SLASH_TIME
	_slash.visible = true
	_animator.trigger(&"attack")
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
	var model := Kit.spawn(MODEL)
	_visual.add_child(model)
	_animator = HunterAnimator.new(model)

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
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.position.y = 2.0
	add_child(light)
