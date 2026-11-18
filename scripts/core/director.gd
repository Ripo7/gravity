class_name Director
extends Node
## Scripted runs, for clips and measurements:
##   --mode=play --steps="p0,-1,2;j;w1;h;w0.5;h" [--from=x,y,z]
##        steps separated by ";": "w<seconds>" wait, "m<x,y,z>" go there,
##        "a@x,y,z" look there, "f<seconds>" run forward, "r<seconds>"
##        sprint forward, "p<x>,<y>,<seconds>[,1]" push the stick (y -1 is
##        forward; 1: sprint), "j" jump, "h" punch, "k" kick,
##        "t<degrees>,<seconds>" turn the camera to the left.
##   --mode=still [--pos=x,y,z --at=x,y,z --wait=S]   just look
## --prof prints the cost of the physics once a second (PROF lines) and
## how the steps are spread at the end (STEPS).

## ms: a physics step longer than this on a desktop is a hitch on a phone.
const SLOW_STEP := 6.0

var options := {}
var world: Main
var player: Player


func _ready() -> void:
	world = get_parent() as Main
	player = world.player
	if options.has("prof"):
		_profile()
	match options.get("mode", ""):
		"play":
			_play()
		"still":
			_still()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true, false).timeout


func _place(at: Vector3, target: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.look_at_point(target)
	player.facing = player.yaw


func _profile() -> void:
	world.clock.keep_history = true
	while true:
		await _wait(1.0)
		print("PROF physics %.2f ms/step (worst %.2f)" % [world.clock.avg_ms, world.clock.worst_ms])


func _play() -> void:
	if options.has("from"):
		player.global_position = _vec(options["from"])
	await _wait(0.5)
	for spec: String in String(options.get("steps", "")).split(";", false):
		var kind := spec.substr(0, 1)
		if kind == "w":
			await _wait(float(spec.substr(1)))
		elif kind == "m":
			player.global_position = _vec(spec.substr(1))
		elif kind == "a":
			player.look_at_point(_vec(spec.substr(2)))
		elif kind == "f" or kind == "r":
			player.touch_move = Vector2(0, -1)
			player.touch_sprint = kind == "r"
			await _wait(float(spec.substr(1)))
			player.touch_move = Vector2.ZERO
			player.touch_sprint = false
			print("WALKED to %s (on floor: %s)" % [player.global_position, player.is_on_floor()])
		elif kind == "p":
			var push := spec.substr(1).split_floats(",")
			player.touch_move = Vector2(push[0], push[1])
			player.touch_sprint = push.size() > 3
			await _wait(push[2])
			player.touch_move = Vector2.ZERO
			player.touch_sprint = false
		elif kind == "j":
			player.touch_jump = true
		elif kind == "h":
			player.touch_punch = true
		elif kind == "k":
			player.touch_kick = true
		elif kind == "t":
			var turn := spec.substr(1).split_floats(",")
			var left := turn[1]
			while left > 0.0:
				await get_tree().physics_frame
				var dt := get_physics_process_delta_time()
				player.look(Vector2(deg_to_rad(turn[0]) * dt / turn[1], 0))
				left -= dt
	_end("PLAY_DONE")


func _still() -> void:
	if options.has("pos"):
		_place(_vec(options["pos"]), _vec(options.get("at", "0,1.5,0")))
	await _wait(float(options.get("wait", "2.0")))
	_end("STILL_DONE")


func _end(tag: String) -> void:
	print("%s at=%s" % [tag, player.global_position.snappedf(0.01)])
	if options.has("prof"):
		# Every step of the run, sorted: the mean hides the hitches.
		var steps := world.clock.history.duplicate()
		steps.sort()
		var n := steps.size()
		var slow := 0
		for ms in steps:
			if ms > SLOW_STEP:
				slow += 1
		print(
			(
				"STEPS %d  median %.2f ms  99%% under %.2f ms  slowest %.2f ms  over %.0f ms: %d"
				% [n, steps[n / 2], steps[n * 99 / 100], steps[n - 1], SLOW_STEP, slow]
			)
		)
	get_tree().quit()


static func _vec(text: String) -> Vector3:
	var f := text.split_floats(",")
	return Vector3(f[0], f[1], f[2])
