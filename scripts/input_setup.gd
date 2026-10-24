class_name InputSetup
extends RefCounted
## Déclare les actions au lancement. Touches physiques : ZQSD sur AZERTY, WASD sur QWERTY.

const DEADZONE := 0.25


static func ensure_actions() -> void:
	_add_keys(&"move_up", [KEY_W, KEY_UP])
	_add_keys(&"move_down", [KEY_S, KEY_DOWN])
	_add_keys(&"move_left", [KEY_A, KEY_LEFT])
	_add_keys(&"move_right", [KEY_D, KEY_RIGHT])
	_add_keys(&"dash", [KEY_SPACE])
	_add_keys(&"attack", [KEY_J])
	_add_keys(&"interact", [KEY_E])
	_add_keys(&"restart", [KEY_R])

	_add_axis(&"move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis(&"move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_button(&"dash", JOY_BUTTON_A)
	_add_joy_button(&"attack", JOY_BUTTON_X)
	_add_joy_button(&"interact", JOY_BUTTON_Y)
	_add_joy_button(&"restart", JOY_BUTTON_START)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	_ensure_action(&"attack")
	InputMap.action_add_event(&"attack", click)


static func _add_keys(action: StringName, keys: Array) -> void:
	_ensure_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


static func _add_axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	_ensure_action(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	InputMap.action_add_event(action, event)


static func _add_joy_button(action: StringName, button: JoyButton) -> void:
	_ensure_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


static func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
