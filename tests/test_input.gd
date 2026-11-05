extends TestCase

const LaunchScript := preload("res://scripts/core/launch.gd")

const REQUIRED := [
	"move_forward", "move_back", "move_left", "move_right", "jump", "cast", "shield", "reset_arena"
]


func test_actions_have_keyboard_and_gamepad() -> void:
	for action: String in REQUIRED:
		check(InputMap.has_action(action), "%s exists" % action)
		var kbm := false
		var pad := false
		for e in InputMap.action_get_events(action):
			kbm = kbm or e is InputEventKey or e is InputEventMouseButton
			pad = pad or e is InputEventJoypadButton or e is InputEventJoypadMotion
		check(kbm, "%s has keyboard/mouse" % action)
		check(pad, "%s has gamepad" % action)


func test_launch_option_parsing() -> void:
	var opts: Dictionary = LaunchScript.parse(PackedStringArray(["--mode=bench", "--fast"]))
	check_eq(opts.get("mode"), "bench", "key=value")
	check_eq(opts.get("fast"), "true", "flag")
	var q: Dictionary = LaunchScript.parse_query("?mode=bench&max=900")
	check_eq(q.get("max"), "900", "query string")
