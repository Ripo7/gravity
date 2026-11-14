extends Node
## Registers every input action in code so bindings are reviewable and the
## same for keyboard/mouse and gamepad.

const DEADZONE := 0.2

## action -> list of events. Keys use physical keycodes so WASD works on AZERTY.
var _bindings := {
	"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
	"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
	"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
	"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
	"look_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
	"look_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
	"look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
	"look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
	"jump": [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
	"sprint": [_key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_STICK)],
	"fire":
	[_mouse(MOUSE_BUTTON_LEFT), _key(KEY_F), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), _button(JOY_BUTTON_X)],
	"rebuild": [_key(KEY_R), _button(JOY_BUTTON_BACK)],
	"release_mouse": [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)],
}


func _enter_tree() -> void:
	for action: String in _bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		for event: InputEvent in _bindings[action]:
			InputMap.action_add_event(action, event)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e
