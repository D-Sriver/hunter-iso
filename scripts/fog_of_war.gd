class_name FogOfWar
extends Node3D
## Brouillard de guerre : le joueur ne voit que ce qui est dans son cône de vision (et un petit
## cercle autour de lui), les murs et les baies serveur projettent des ombres. Une zone vue reste
## claire un instant puis passe sous un voile gris ; ce qui n'a jamais été vu reste noir.
##
## La vision est calculée sur une grille fine (4 cellules par tuile) en lançant des rayons
## depuis le joueur, puis envoyée au shader sous forme de texture.

const SHADER := preload("res://shaders/fog_of_war.gdshader")
const CELLS_PER_TILE := 4
const CONE_RANGE := 12.0
const CONE_HALF_ANGLE := deg_to_rad(55.0)
const CONE_RAY_STEP := deg_to_rad(1.2)
const AROUND_RANGE := 3.0
const AROUND_RAY_STEP := deg_to_rad(6.0)
const MARCH_STEP := 0.25
const UPDATE_INTERVAL := 0.05
## Une zone qui sort du champ reste claire LINGER_TIME secondes puis se voile en FADE_TIME.
const LINGER_TIME := 0.6
const FADE_TIME := 0.8
const VEIL := 0.5
## Mobilier qui bloque la vue, avec sa demi-emprise au sol (x, z) en mètres.
const BLOCKING_FURNITURE := {"rack": Vector2(0.97, 0.5), "pillar": Vector2(0.45, 0.45)}

var _cell_size: float
var _origin: Vector2
var _width: int
var _height: int
var _opaque := PackedByteArray()
var _seen_at := PackedFloat32Array()
var _view_tick := PackedInt32Array()
var _pixels := PackedByteArray()
## Cellules encore en train de s'estomper (index -> true).
var _fading := {}
var _tick := 0
var _time := 0.0
var _timer := 0.0
var _image: Image
var _texture: ImageTexture


func setup(level: LevelGenerator, tile_size: float) -> void:
	_cell_size = tile_size / CELLS_PER_TILE
	_origin = Vector2(-tile_size * 0.5, -tile_size * 0.5)
	_width = level.width * CELLS_PER_TILE
	_height = level.height * CELLS_PER_TILE
	var count := _width * _height
	_opaque.resize(count)
	_seen_at.resize(count)
	_seen_at.fill(-1.0)
	_view_tick.resize(count)
	_view_tick.fill(-1)
	_pixels.resize(count)
	_build_opaque(level, tile_size)

	_image = Image.create_from_data(_width, _height, false, Image.FORMAT_L8, _pixels)
	_texture = ImageTexture.create_from_image(_image)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material.set_shader_parameter("fog_map", _texture)
	material.set_shader_parameter("map_origin", _origin)
	material.set_shader_parameter("map_size", Vector2(_width, _height) * _cell_size)
	material.set_shader_parameter("veil", VEIL)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.material_override = material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Le quad est replacé sur tout l'écran par le shader : il ne doit jamais être coupé.
	screen.extra_cull_margin = 16384.0
	add_child(screen)


## Recalcule la vision depuis `eye`, regard tourné vers `facing`.
func update(delta: float, eye: Vector3, facing: Vector3) -> void:
	_time += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	_tick += 1
	var start := Vector2(eye.x, eye.z)
	var heading := atan2(facing.z, facing.x)
	var angle := -CONE_HALF_ANGLE
	while angle <= CONE_HALF_ANGLE:
		_cast(start, heading + angle, CONE_RANGE)
		angle += CONE_RAY_STEP
	angle = 0.0
	while angle < TAU:
		_cast(start, angle, AROUND_RANGE)
		angle += AROUND_RAY_STEP
	_refresh_pixels()


## Vrai si ce point est dans le champ de vision en ce moment : sert à cacher les rivaux.
func is_in_view(point: Vector3) -> bool:
	var index := _index_at(Vector2(point.x, point.z))
	return index >= 0 and _view_tick[index] == _tick


func _cast(start: Vector2, angle: float, max_range: float) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var travelled := 0.0
	while travelled <= max_range:
		var index := _index_at(start + direction * travelled)
		if index < 0:
			return
		if _view_tick[index] != _tick:
			_view_tick[index] = _tick
			_seen_at[index] = _time
			_fading[index] = true
		# La cellule qui bloque est éclairée (on voit la face du mur), pas celles derrière.
		if _opaque[index] == 1:
			return
		travelled += MARCH_STEP


func _refresh_pixels() -> void:
	for index: int in _fading.keys():
		var age := _time - _seen_at[index]
		var fade := clampf((age - LINGER_TIME) / FADE_TIME, 0.0, 1.0)
		_pixels[index] = roundi(lerpf(1.0, VEIL, fade) * 255.0)
		if fade >= 1.0:
			_fading.erase(index)
	_image.set_data(_width, _height, false, Image.FORMAT_L8, _pixels)
	_texture.update(_image)


func _build_opaque(level: LevelGenerator, tile_size: float) -> void:
	for z in _height:
		for x in _width:
			var tile := Vector2i(
				floori(float(x) / CELLS_PER_TILE), floori(float(z) / CELLS_PER_TILE)
			)
			_opaque[z * _width + x] = 0 if level.is_ground(tile) else 1
	for tile: Vector2i in level.furniture:
		var kind := String(level.furniture[tile])
		if not BLOCKING_FURNITURE.has(kind):
			continue
		var half: Vector2 = BLOCKING_FURNITURE[kind]
		var center := Vector2(tile.x, tile.y) * tile_size
		for z in range(tile.y * CELLS_PER_TILE, (tile.y + 1) * CELLS_PER_TILE):
			for x in range(tile.x * CELLS_PER_TILE, (tile.x + 1) * CELLS_PER_TILE):
				var offset := _cell_center(x, z) - center
				if absf(offset.x) < half.x and absf(offset.y) < half.y:
					_opaque[z * _width + x] = 1


func _cell_center(x: int, z: int) -> Vector2:
	return _origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * _cell_size


func _index_at(point: Vector2) -> int:
	var cell := ((point - _origin) / _cell_size).floor()
	if cell.x < 0.0 or cell.y < 0.0 or cell.x >= _width or cell.y >= _height:
		return -1
	return int(cell.y) * _width + int(cell.x)
