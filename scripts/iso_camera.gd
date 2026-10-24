class_name IsoCamera
extends Camera3D
## Caméra orthographique en vue isométrique, qui suit sa cible en douceur. Quand le joueur
## vise, elle glisse vers la visée pour montrer ce qu'il y a devant lui.

const OFFSET := Vector3(15.0, 15.0, 15.0)
const FOLLOW_SPEED := 6.0
## Part de l'écart souris / centre de l'écran que la caméra rattrape, et décalage maximal.
const MOUSE_LEAD := 0.35
const MAX_LEAD := 5.0
const STICK_LEAD := 3.5

var target: Node3D

var _focus := Vector3.ZERO


func _init(view_size: float) -> void:
	projection = PROJECTION_ORTHOGONAL
	size = view_size
	far = 200.0


## Place la caméra directement sur la cible, sans glissement.
func snap() -> void:
	_focus = target.global_position
	_place()


func _process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_position + _lead()
	_focus = _focus.lerp(goal, minf(delta * FOLLOW_SPEED, 1.0))
	_place()


## Point du sol (y = 0) sous la souris.
func mouse_ground_point() -> Vector3:
	return _ground_point(get_viewport().get_mouse_position())


func _lead() -> Vector3:
	var player := target as Player
	if player == null or not player.is_aiming():
		return Vector3.ZERO
	if player.aim_mode == Player.Aim.STICK:
		return player.facing * STICK_LEAD
	# Écart entre la souris et le centre de l'écran, mesuré au sol : il ne dépend pas de la
	# position de la caméra, donc pas d'emballement quand elle se déplace.
	var center := get_viewport().get_visible_rect().size * 0.5
	var offset := mouse_ground_point() - _ground_point(center)
	return (offset * MOUSE_LEAD).limit_length(MAX_LEAD)


func _ground_point(screen_point: Vector2) -> Vector3:
	var origin := project_ray_origin(screen_point)
	var direction := project_ray_normal(screen_point)
	if absf(direction.y) < 0.0001:
		return origin
	return origin + direction * (-origin.y / direction.y)


func _place() -> void:
	global_position = _focus + OFFSET
	look_at(_focus, Vector3.UP)
