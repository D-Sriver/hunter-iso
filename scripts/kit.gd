class_name Kit
extends RefCounted
## Charge les pièces modélisées dans Blender (assets/kit/*.glb, générées par blender/kit.py)
## et leur applique le rendu anime : ombrage en deux tons et contour sombre.

const DIRECTORY := "res://assets/kit/"
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
## Pas de contour sur ce qui brille, sur les sols (chaque dalle tracerait un quadrillage)
## ni sur les détails peints du visage.
const NO_OUTLINE_PREFIXES := ["neon", "screen", "relic", "floor", "grating", "mouth"]
## Largeur de la transition ombre / lumière : plus c'est petit, plus la coupure est franche.
const TOON_EDGE := 0.06

static var _scenes := {}
static var _outline: ShaderMaterial


## Instancie une pièce du kit par son nom de fichier, sans l'extension.
static func spawn(piece: String) -> Node3D:
	if not _scenes.has(piece):
		_scenes[piece] = load(DIRECTORY + piece + ".glb")
	var node := (_scenes[piece] as PackedScene).instantiate() as Node3D
	_stylize(node)
	return node


## Les maillages sont partagés entre instances : on ne convertit chaque matériau qu'une fois.
static func _stylize(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null or mesh.has_meta(&"toon"):
			continue
		mesh.set_meta(&"toon", true)
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null:
				_to_toon(material)


static func _to_toon(material: BaseMaterial3D) -> void:
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.metallic = 0.0
	material.roughness = TOON_EDGE
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		# Les yeux sont des plaques détourées : un seuil net évite les soucis de tri.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		return
	if _wants_outline(material.resource_name):
		material.next_pass = _outline_material()


static func _wants_outline(material_name: String) -> bool:
	if material_name.contains("_eye"):
		return false
	for prefix in NO_OUTLINE_PREFIXES:
		if material_name.begins_with(prefix):
			return false
	return true


static func _outline_material() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = OUTLINE_SHADER
	return _outline
