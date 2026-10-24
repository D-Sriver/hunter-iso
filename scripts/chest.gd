class_name Chest
extends Node3D
## Coffre de butin à revendre au hub. L'ouvrir prend du temps et fait du bruit.

const GLOW_COLOR := Color(1.0, 0.75, 0.2)

var loot_value := 0
var opened := false

var _model: Node3D
var _light: OmniLight3D


func setup(value: int) -> void:
	loot_value = value


func _ready() -> void:
	_model = Kit.spawn("loot_chest")
	add_child(_model)

	_light = OmniLight3D.new()
	_light.light_color = GLOW_COLOR
	_light.light_energy = 1.0
	_light.omni_range = 2.5
	_light.position.y = 1.0
	add_child(_light)


## Ouvre le coffre et rend la valeur du butin.
func open() -> int:
	opened = true
	_model.queue_free()
	_model = Kit.spawn("loot_chest_open")
	add_child(_model)
	_light.visible = false
	return loot_value
