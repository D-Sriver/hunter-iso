class_name Chest
extends Node3D
## Coffre de butin à revendre au hub. L'ouvrir prend du temps et fait du bruit.

const CLOSED_COLOR := Color(1.0, 0.8, 0.2)
const OPENED_COLOR := Color(0.25, 0.22, 0.18)

var loot_value := 0
var opened := false

var _lid: MeshInstance3D
var _light: OmniLight3D


func setup(value: int) -> void:
	loot_value = value


func _ready() -> void:
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.9, 0.45, 0.6)
	base_mesh.material = Materials.neon(CLOSED_COLOR, 0.4)
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	base.position.y = 0.225
	add_child(base)

	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(0.95, 0.15, 0.65)
	lid_mesh.material = Materials.neon(CLOSED_COLOR, 1.2)
	_lid = MeshInstance3D.new()
	_lid.mesh = lid_mesh
	_lid.position.y = 0.53
	add_child(_lid)

	_light = OmniLight3D.new()
	_light.light_color = CLOSED_COLOR
	_light.light_energy = 1.0
	_light.omni_range = 2.5
	_light.position.y = 1.0
	add_child(_light)


## Ouvre le coffre et rend la valeur du butin.
func open() -> int:
	opened = true
	_lid.position = Vector3(0.0, 0.75, -0.3)
	_lid.rotation.x = -1.1
	_lid.material_override = Materials.flat(OPENED_COLOR)
	_light.visible = false
	return loot_value
