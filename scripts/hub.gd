class_name Hub
extends Node3D
## Le hub entre les runs : une planque où la relique qui parle commente tes exploits, où le
## terminal vend des implants et d'où la plateforme verte lance la mission suivante.

enum Mode { WALK, TALK, SHOP }

const RUN_SCENE := "res://scenes/main.tscn"
const SIZE := Vector2i(7, 5)
const TILE_SIZE := 2.0
const CAMERA_SIZE := 13.0
const RELIC_SPOT := Vector3(6.0, 0.0, 0.8)
const TERMINAL_SPOT := Vector3(0.4, 0.0, 4.0)
const EXIT_SPOT := Vector3(10.0, 0.0, 7.0)
const PLAYER_SPOT := Vector3(6.0, 0.0, 5.0)
const TALK_RANGE := 2.4
const SHOP_RANGE := 1.8
const EXIT_RANGE := 1.2
const RELIC_COLOR := Color(0.3, 1.0, 1.0)
const EXIT_COLOR := Color(0.25, 1.0, 0.35)
## Murs du fond, de gauche à droite à l'écran.
const BACK_WALLS := [
	"wall_screens",
	"wall_panel",
	"wall_neon_pink",
	"wall_panel",
	"wall_pipes",
	"wall_screens",
	"wall_panel",
]
const SIDE_WALLS := ["wall_pipes", "wall_panel", "wall_neon_teal", "wall_panel", "wall_pipes"]
const ROOM_LIGHTS := [
	[Vector3(2.0, 2.4, 0.0), Color(1.0, 0.3, 0.65)],
	[Vector3(10.0, 2.4, 0.0), Color(0.25, 1.0, 0.85)],
	[Vector3(0.0, 2.4, 6.0), Color(1.0, 0.3, 0.65)],
]

var _player: Player
var _relic: Node3D
var _relic_mark: Label3D
var _ui: HubUi
var _mode := Mode.WALK
var _lines: Array = []
var _shop_selection := 0


func _ready() -> void:
	InputSetup.ensure_actions()
	Ambience.setup(self)
	_build_room()
	_build_props()
	_player = Player.new()
	add_child(_player)
	_player.global_position = PLAYER_SPOT
	_player.facing = Vector3(0.0, 0.0, -1.0)
	var camera := IsoCamera.new(CAMERA_SIZE)
	camera.target = _player
	add_child(camera)
	camera.snap()
	_ui = HubUi.new()
	add_child(_ui)
	_ui.set_credits(SaveData.load_credits())
	_lines = _pending_lines()


func _process(delta: float) -> void:
	_relic.rotate_y(delta * 1.5)
	_relic.position.y = 1.25 + sin(Time.get_ticks_msec() * 0.003) * 0.06
	_relic_mark.text = "!" if not _lines.is_empty() else "..."
	match _mode:
		Mode.WALK:
			_update_walk()
		Mode.TALK:
			_update_talk()
		Mode.SHOP:
			_update_shop()


# --- Modes ---


func _update_walk() -> void:
	var position_now := _player.global_position
	if _near(position_now, RELIC_SPOT, TALK_RANGE):
		_ui.set_hint("E : parler à la relique")
		if Input.is_action_just_pressed(&"interact"):
			_start_talk()
	elif _near(position_now, TERMINAL_SPOT, SHOP_RANGE):
		_ui.set_hint("E : acheter des implants")
		if Input.is_action_just_pressed(&"interact"):
			_open_shop()
	elif _near(position_now, EXIT_SPOT, EXIT_RANGE):
		_ui.set_hint("E : partir en mission")
		if Input.is_action_just_pressed(&"interact"):
			get_tree().change_scene_to_file(RUN_SCENE)
	else:
		_ui.set_hint("")


func _start_talk() -> void:
	if _lines.is_empty():
		_lines = [RelicLines.BANTER.pick_random()]
	_set_mode(Mode.TALK)
	_ui.show_line(_lines.pop_front())


func _update_talk() -> void:
	if not Input.is_action_just_pressed(&"interact"):
		return
	if _ui.is_typing():
		_ui.finish_typing()
	elif _lines.is_empty():
		_ui.hide_dialogue()
		_set_mode(Mode.WALK)
	else:
		_ui.show_line(_lines.pop_front())


func _open_shop() -> void:
	_set_mode(Mode.SHOP)
	_ui.show_shop(_shop_selection, "")


func _update_shop() -> void:
	var count := Implants.CATALOG.size()
	if Input.is_action_just_pressed(&"move_up"):
		_shop_selection = (_shop_selection + count - 1) % count
		_ui.show_shop(_shop_selection, "")
	elif Input.is_action_just_pressed(&"move_down"):
		_shop_selection = (_shop_selection + 1) % count
		_ui.show_shop(_shop_selection, "")
	elif Input.is_action_just_pressed(&"interact"):
		var entry: Dictionary = Implants.CATALOG[_shop_selection]
		var message := "Installé : %s." % entry["name"]
		if Implants.next_cost(entry) < 0:
			message = "Déjà au maximum."
		elif not Implants.buy(entry):
			message = "Pas assez de crédits."
		_ui.set_credits(SaveData.load_credits())
		_ui.show_shop(_shop_selection, message)
	elif Input.is_action_just_pressed(&"dash") or Input.is_action_just_pressed(&"ui_cancel"):
		_ui.hide_shop()
		_set_mode(Mode.WALK)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_player.set_controls_enabled(mode == Mode.WALK)


## Ce que la relique a sur le cœur en arrivant : l'intro la première fois, puis un commentaire
## sur la dernière run. Une fois dit, c'est noté dans la sauvegarde.
func _pending_lines() -> Array:
	if not SaveData.intro_seen():
		SaveData.mark_intro_seen()
		return RelicLines.INTRO.duplicate()
	var result := SaveData.last_result()
	SaveData.clear_last_result()
	return RelicLines.AFTER_RUN.get(result, []).duplicate()


func _near(a: Vector3, b: Vector3, distance: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < distance


# --- Décor ---


## Une seule salle en diorama : murs pleins au fond et à gauche, murets côté caméra.
func _build_room() -> void:
	var half := TILE_SIZE * 0.5
	var far_x := SIZE.x * TILE_SIZE - half
	var far_z := SIZE.y * TILE_SIZE - half
	for x in SIZE.x:
		for z in SIZE.y:
			_place("floor_room", Vector3(x * TILE_SIZE, 0.0, z * TILE_SIZE), 0.0)
	for x in SIZE.x:
		_place(BACK_WALLS[x], Vector3(x * TILE_SIZE, 0.0, -half), 0.0)
		_place("wall_post", Vector3(x * TILE_SIZE - half, 0.0, -half), 0.0)
		_place("wall_stub", Vector3(x * TILE_SIZE, 0.0, far_z), 0.0)
	_place("wall_post", Vector3(far_x, 0.0, -half), 0.0)
	for z in SIZE.y:
		_place(SIDE_WALLS[z], Vector3(-half, 0.0, z * TILE_SIZE), PI / 2.0)
		_place("wall_post", Vector3(-half, 0.0, z * TILE_SIZE + half), 0.0)
		_place("wall_stub", Vector3(far_x, 0.0, z * TILE_SIZE), PI / 2.0)

	var body := StaticBody3D.new()
	body.collision_layer = LevelBuilder.WALL_LAYER
	body.collision_mask = 0
	add_child(body)
	var center := Vector3((far_x - half) * 0.5, 1.5, (far_z - half) * 0.5)
	var width := far_x + half
	var depth := far_z + half
	for side in [
		[Vector3(center.x, 1.5, -half - 0.5), Vector3(width, 3.0, 1.0)],
		[Vector3(center.x, 1.5, far_z + 0.5), Vector3(width, 3.0, 1.0)],
		[Vector3(-half - 0.5, 1.5, center.z), Vector3(1.0, 3.0, depth)],
		[Vector3(far_x + 0.5, 1.5, center.z), Vector3(1.0, 3.0, depth)],
	]:
		_add_collider(body, side[0], side[1])

	for spot in ROOM_LIGHTS:
		var light := OmniLight3D.new()
		light.position = spot[0]
		light.light_color = spot[1]
		light.light_energy = 2.0
		light.omni_range = 8.0
		add_child(light)


func _build_props() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LevelBuilder.WALL_LAYER
	body.collision_mask = 0
	add_child(body)

	# La relique, sur son piédestal au fond de la pièce.
	_place("pedestal", RELIC_SPOT, 0.0)
	_add_collider(body, RELIC_SPOT + Vector3(0.0, 0.4, 0.0), Vector3(1.2, 0.8, 1.2))
	_relic = _place("relic", RELIC_SPOT + Vector3(0.0, 1.25, 0.0), 0.0)
	var glow := OmniLight3D.new()
	glow.light_color = RELIC_COLOR
	glow.light_energy = 2.5
	glow.omni_range = 5.0
	glow.position = RELIC_SPOT + Vector3(0.0, 1.6, 0.0)
	add_child(glow)
	_relic_mark = _make_label(RELIC_SPOT + Vector3(0.0, 2.3, 0.0), RELIC_COLOR, 64)

	# Le terminal des implants, contre le mur de gauche.
	_place("terminal", TERMINAL_SPOT, PI / 2.0)
	_add_collider(body, TERMINAL_SPOT + Vector3(0.0, 0.6, 0.0), Vector3(0.6, 1.2, 0.7))
	_make_label(TERMINAL_SPOT + Vector3(0.0, 2.1, 0.0), Color(1.0, 0.4, 0.75), 40).text = ("IMPLANTS")

	# Départ en mission, dans le coin devant à droite.
	_place("exit_pad", EXIT_SPOT, 0.0)
	_make_label(EXIT_SPOT + Vector3(0.0, 1.6, 0.0), EXIT_COLOR, 40).text = "MISSION"
	var exit_light := OmniLight3D.new()
	exit_light.light_color = EXIT_COLOR
	exit_light.light_energy = 2.0
	exit_light.omni_range = 4.0
	exit_light.position = EXIT_SPOT + Vector3(0.0, 1.0, 0.0)
	add_child(exit_light)

	# Un peu de vie : bureau, caisses, baies serveur.
	_place("desk", Vector3(2.4, 0.0, -0.1), 0.0)
	_add_collider(body, Vector3(2.4, 0.5, -0.1), Vector3(1.6, 1.0, 0.8))
	_place("crate_stack", Vector3(11.6, 0.0, 0.2), -0.3)
	_add_collider(body, Vector3(11.6, 0.75, 0.2), Vector3(1.7, 1.5, 0.9))
	_place("barrel", Vector3(12.2, 0.0, 1.8), 0.0)
	_add_collider(body, Vector3(12.2, 0.45, 1.8), Vector3(0.6, 0.9, 0.6))
	for z in [6.4, 7.4]:
		_place("server_rack", Vector3(-0.3, 0.0, z), PI / 2.0)
	_add_collider(body, Vector3(-0.3, 1.1, 6.9), Vector3(1.0, 2.2, 1.9))


func _place(piece: String, at: Vector3, rotation_y: float) -> Node3D:
	var node := Kit.spawn(piece)
	add_child(node)
	node.position = at
	node.rotation.y = rotation_y
	return node


func _add_collider(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = at
	body.add_child(collider)


func _make_label(at: Vector3, color: Color, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = font_size
	label.outline_size = 8
	label.pixel_size = 0.01
	label.modulate = color
	label.position = at
	add_child(label)
	return label
