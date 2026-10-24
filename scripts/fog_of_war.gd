class_name FogOfWar
extends Node3D
## Brouillard de guerre : le joueur ne voit que ce qui est dans son cône de vision (et un petit
## cercle autour de lui), les murs et les baies serveur projettent des ombres. Une zone vue reste
## claire un instant puis passe sous un voile gris ; ce qui n'a jamais été vu reste noir.
##
## Tout le calcul de la vue se fait sur la carte graphique, pixel par pixel et à chaque image :
## une carte vue de dessus (`vision_map.gdshader`) garde la mémoire de ce qui a été vu, puis un
## quad plein écran (`fog_of_war.gdshader`) assombrit la scène d'après cette carte.

const VISION_SHADER := preload("res://shaders/vision_map.gdshader")
const FOG_SHADER := preload("res://shaders/fog_of_war.gdshader")
## Grille des obstacles à la vue : 4 cellules de 50 cm par tuile.
const CELLS_PER_TILE := 4
## Résolution de la carte de vision : 8 pixels par mètre, des ombres nettes sans escalier.
const PIXELS_PER_METER := 8.0
const CONE_RANGE := 12.0
const CONE_HALF_ANGLE := deg_to_rad(55.0)
## Bord du cône adouci sur quelques degrés.
const CONE_SOFTNESS := deg_to_rad(5.0)
const AROUND_RANGE := 3.0
## Le cône suit le regard en douceur plutôt que de sauter d'une direction à l'autre.
const TURN_SMOOTHING := 14.0
## Une zone qui sort du champ reste claire LINGER_TIME secondes puis se voile en FADE_TIME.
const LINGER_TIME := 0.6
const FADE_TIME := 0.8
## Mobilier qui bloque la vue, avec sa demi-emprise au sol (x, z) en mètres.
const BLOCKING_FURNITURE := {"rack": Vector2(0.97, 0.5), "pillar": Vector2(0.45, 0.45)}

var _cell_size: float
var _origin: Vector2
var _width: int
var _height: int
var _opaque := PackedByteArray()
var _eye := Vector2.ZERO
var _heading := Vector2(0.0, 1.0)
var _vision: ShaderMaterial


func setup(level: LevelGenerator, tile_size: float) -> void:
	_cell_size = tile_size / CELLS_PER_TILE
	_origin = Vector2(-tile_size * 0.5, -tile_size * 0.5)
	_width = level.width * CELLS_PER_TILE
	_height = level.height * CELLS_PER_TILE
	_opaque.resize(_width * _height)
	_build_opaque(level, tile_size)
	var map_size := Vector2(_width, _height) * _cell_size
	var map := _build_vision_map(map_size)

	var fog := ShaderMaterial.new()
	fog.shader = FOG_SHADER
	fog.render_priority = Material.RENDER_PRIORITY_MAX
	fog.set_shader_parameter("vision_map", map.get_texture())
	fog.set_shader_parameter("map_origin", _origin)
	fog.set_shader_parameter("map_size", map_size)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.material_override = fog
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Le quad est replacé sur tout l'écran par le shader : il ne doit jamais être coupé.
	screen.extra_cull_margin = 16384.0
	add_child(screen)


## Place l'œil en `eye`, regard tourné vers `facing`.
func update(delta: float, eye: Vector3, facing: Vector3) -> void:
	_eye = Vector2(eye.x, eye.z)
	var target := Vector2(facing.x, facing.z)
	if target.length_squared() > 0.0001:
		var weight := 1.0 - exp(-TURN_SMOOTHING * delta)
		_heading = Vector2.from_angle(lerp_angle(_heading.angle(), target.angle(), weight))
	_vision.set_shader_parameter("eye", _eye)
	_vision.set_shader_parameter("heading", _heading)
	_vision.set_shader_parameter("decay", delta / FADE_TIME)


## Vrai si ce point est dans le champ de vision en ce moment : sert à cacher les rivaux.
## Mêmes règles que le shader, pour qu'un rival apparaisse pile quand sa zone s'éclaire.
func is_in_view(point: Vector3) -> bool:
	var target := Vector2(point.x, point.z)
	var to_point := target - _eye
	var dist := to_point.length()
	if dist > AROUND_RANGE:
		if dist > CONE_RANGE or to_point.normalized().dot(_heading) < cos(CONE_HALF_ANGLE):
			return false
	return _has_line_of_sight(_eye, target)


func _build_vision_map(map_size: Vector2) -> SubViewport:
	var opacity := Image.create_from_data(_width, _height, false, Image.FORMAT_L8, _opaque)
	_vision = ShaderMaterial.new()
	_vision.shader = VISION_SHADER
	_vision.set_shader_parameter("opacity", ImageTexture.create_from_image(opacity))
	_vision.set_shader_parameter("grid_size", Vector2i(_width, _height))
	_vision.set_shader_parameter("cell_size", _cell_size)
	_vision.set_shader_parameter("map_origin", _origin)
	_vision.set_shader_parameter("map_size", map_size)
	_vision.set_shader_parameter("cone_cos_outer", cos(CONE_HALF_ANGLE + CONE_SOFTNESS))
	_vision.set_shader_parameter("cone_cos_inner", cos(CONE_HALF_ANGLE - CONE_SOFTNESS))
	_vision.set_shader_parameter("cone_range", CONE_RANGE)
	_vision.set_shader_parameter("around_range", AROUND_RANGE)
	_vision.set_shader_parameter("hold", 1.0 + LINGER_TIME / FADE_TIME)

	# Effacée une seule fois : chaque image relit la précédente pour se souvenir du déjà-vu.
	# En HDR pour garder des valeurs au-dessus de 1 (le temps de rester clair).
	var viewport := SubViewport.new()
	viewport.size = Vector2i((map_size * PIXELS_PER_METER).ceil())
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var canvas := ColorRect.new()
	canvas.size = Vector2(viewport.size)
	canvas.material = _vision
	viewport.add_child(canvas)
	add_child(viewport)
	return viewport


func _build_opaque(level: LevelGenerator, tile_size: float) -> void:
	for z in _height:
		for x in _width:
			var tile := Vector2i(
				floori(float(x) / CELLS_PER_TILE), floori(float(z) / CELLS_PER_TILE)
			)
			_opaque[z * _width + x] = 0 if level.is_ground(tile) else 255
	for tile: Vector2i in level.furniture:
		var kind := String(level.furniture[tile])
		if not BLOCKING_FURNITURE.has(kind):
			continue
		var half: Vector2 = BLOCKING_FURNITURE[kind]
		var center := Vector2(tile.x, tile.y) * tile_size
		for z in range(tile.y * CELLS_PER_TILE, (tile.y + 1) * CELLS_PER_TILE):
			for x in range(tile.x * CELLS_PER_TILE, (tile.x + 1) * CELLS_PER_TILE):
				var offset := _origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * _cell_size - center
				if absf(offset.x) < half.x and absf(offset.y) < half.y:
					_opaque[z * _width + x] = 255


## Même parcours de cellules que `has_line_of_sight` dans le shader.
func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var a := (from - _origin) / _cell_size
	var b := (to - _origin) / _cell_size
	var cell := Vector2i(a.floor())
	var goal := Vector2i(b.floor())
	var d := b - a
	var step := Vector2i(d.sign())
	var inv := Vector2(
		1.0 / absf(d.x) if absf(d.x) > 1e-6 else 1e9, 1.0 / absf(d.y) if absf(d.y) > 1e-6 else 1e9
	)
	var f := a - a.floor()
	var t_max := Vector2(1.0 - f.x if d.x > 0.0 else f.x, 1.0 - f.y if d.y > 0.0 else f.y) * inv
	for i in 96:
		if cell == goal:
			return true
		if t_max.x < t_max.y:
			t_max.x += inv.x
			cell.x += step.x
		else:
			t_max.y += inv.y
			cell.y += step.y
		if cell == goal:
			return true
		if _is_opaque(cell):
			return false
	return true


func _is_opaque(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _width or cell.y >= _height:
		return true
	return _opaque[cell.y * _width + cell.x] > 0
