class_name IsoCamera
extends Camera3D
## Caméra orthographique en vue isométrique, qui suit sa cible en douceur.

const OFFSET := Vector3(15.0, 15.0, 15.0)
const FOLLOW_SPEED := 6.0

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
	_focus = _focus.lerp(target.global_position, minf(delta * FOLLOW_SPEED, 1.0))
	_place()


func _place() -> void:
	global_position = _focus + OFFSET
	look_at(_focus, Vector3.UP)
