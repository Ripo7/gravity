class_name Director
extends Node
## Scripted runs, for clips and measurements:
##   --mode=play --steps="a@x,y,z;o;w1.5" [--from=x,y,z]
##        steps separated by ";": "o" a shot ("o@x,y,z" aims first),
##        "a@x,y,z" look there ("a@d", "o@d": at the other brute), "m<x,y,z>" go
##        there, "w<seconds>" wait,
##        "f<seconds>" run forward, "r<seconds>" sprint forward,
##        "p<x>,<y>,<seconds>[,1]" push the stick (y -1 is forward; 1: sprint),
##        "j" jump, "h" punch, "k" kick, "u" duck, "x1" / "x0" the other
##        brute attacks or stands there,
##        "t<degrees>,<seconds>" turn the camera to the
##        left, "d@x,y,z" put the other brute there (in the house's space),
##        "c@x0,y0,z0,x1,y1,z1" knock out what stands in that box.
##   --mode=showcase   a fixed tour that takes the house apart
##   --mode=still [--pos=x,y,z --at=x,y,z --wait=S]   just look
##   --mode=check      how loaded the building is as built
## --fight lets the other brute attack (it only stands there otherwise).
## --seed=N makes a run repeatable; --prof prints the cost of the physics
## once a second (PROF lines, read by tools/perf_gate.py).

## ms: a physics step longer than this on a desktop is a hitch on a phone.
const SLOW_STEP := 6.0
## Shots at each stop of the showcase.
const VOLLEY := 6

var options := {}
var world: Main
var player: Player
var _most_awake := 0


func _ready() -> void:
	world = get_parent() as Main
	player = world.player
	world.brute.ai = options.has("fight")
	if options.has("seed"):
		seed(int(options["seed"]))
	if options.has("prof"):
		_profile()
	match options.get("mode", ""):
		"play":
			_play()
		"showcase":
			_showcase()
		"still":
			_still()
		"check":
			_check()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true, false).timeout


func _place(at: Vector3, target: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	_aim(target)
	player.facing = player.yaw


func _aim(target: Vector3) -> void:
	player.look_at_point(target)


func _fire() -> void:
	while player.cooldown_left > 0.0:
		await get_tree().physics_frame
	player.fire()


func _profile() -> void:
	world.clock.keep_history = true
	while true:
		await _wait(1.0)
		var p := world.structure.pieces
		_most_awake = maxi(_most_awake, p.awake)
		print(
			(
				"PROF physics %.2f ms/step (worst %.2f)  pieces %d (awake %d)  standing %d  solve %.2f ms"
				% [
					world.clock.avg_ms,
					world.clock.worst_ms,
					p.live,
					p.awake,
					world.structure.held_count,
					world.structure.solve_usec / 1000.0,
				]
			)
		)


func _play() -> void:
	if options.has("from"):
		player.global_position = _vec(options["from"])
	await _wait(0.5)
	var casts := 0
	for spec: String in String(options.get("steps", "")).split(";", false):
		var kind := spec.substr(0, 1)
		if kind == "w":
			await _wait(float(spec.substr(1)))
		elif kind == "m":
			player.global_position = _vec(spec.substr(1))
		elif kind == "a":
			_aim(_point(spec.substr(2)))
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
		elif kind == "u":
			player.touch_dodge = true
		elif kind == "x":
			world.brute.ai = spec.substr(1) == "1"
		elif kind == "d":
			world.brute.global_position = world.house_at * _vec(spec.substr(2))
		elif kind == "t":
			var turn := spec.substr(1).split_floats(",")
			var left := turn[1]
			while left > 0.0:
				await get_tree().physics_frame
				var dt := get_physics_process_delta_time()
				player.look(Vector2(deg_to_rad(turn[0]) * dt / turn[1], 0))
				left -= dt
		elif kind == "c":
			var box := spec.substr(2).split_floats(",")
			_cut(
				AABB(
					Vector3(box[0], box[1], box[2]),
					Vector3(box[3] - box[0], box[4] - box[1], box[5] - box[2])
				)
			)
		elif kind == "o":
			if spec.contains("@"):
				_aim(_point(spec.split("@")[1]))
			await _fire()
			casts += 1
			await get_tree().physics_frame
			print(
				(
					"CAST %d standing=%d pieces=%d"
					% [casts, world.structure.held_count, world.structure.pieces.live]
				)
			)
	_end("PLAY_DONE")


## Around the house, a volley at each stop: holes in the front, the porch's
## pillars, the sides, the back, then the pillars inside through the holes,
## until the upper floor comes down.
func _showcase() -> void:
	var house := world.house_at
	var stops: Array[Array] = [
		[Vector3(-2.5, 0, 9.5), Vector3(-2.5, 1.4, 3.3)],
		[Vector3(2.7, 0, 9.5), Vector3(2.7, 1.5, 3.3)],
		[Vector3(-7.5, 0, 9.0), Vector3(-4.3, 1.4, 6.7)],
		[Vector3(7.5, 0, 9.0), Vector3(4.3, 1.4, 6.7)],
		[Vector3(-8.5, 0, 0.5), Vector3(-4.3, 1.4, 0.5)],
		[Vector3(-8.5, 0, -2.0), Vector3(-4.3, 1.6, -2.0)],
		[Vector3(8.5, 0, 0.5), Vector3(4.3, 1.4, 0.5)],
		[Vector3(8.5, 0, 2.0), Vector3(4.3, 1.6, 2.0)],
		[Vector3(0, 0, -8.5), Vector3(0, 1.4, -3.3)],
		[Vector3(-3.0, 0, -8.5), Vector3(-3.0, 1.4, -3.3)],
		[Vector3(3.0, 0, -8.5), Vector3(3.0, 1.4, -3.3)],
		[Vector3(0, 0, 10.0), Vector3(0, 1.2, 0.0)],
		[Vector3(-3.0, 0, 10.0), Vector3(-2.5, 1.4, 0.0)],
		[Vector3(3.0, 0, 10.0), Vector3(2.5, 1.4, 0.0)],
	]
	await _wait(0.5)
	for stop in stops:
		var from := house * (stop[0] as Vector3) + Vector3.UP * 0.05
		var target := house * (stop[1] as Vector3)
		_place(from, target)
		await _wait(0.25)
		# Six shots, in two rows of three across what is aimed at.
		var across := (target - from).cross(Vector3.UP).normalized()
		for k in VOLLEY:
			_aim(target + across * (k % 3 - 1) * 0.8 + Vector3.UP * (k / 3 - 0.5) * 1.0)
			await _fire()
		await _wait(1.0)
	await _wait(4.0)
	_end("SHOWCASE_DONE")


## Knocks out every standing shard centred in `box` (they drop where they are).
func _cut(box: AABB) -> void:
	var s := world.structure
	for i in s.count:
		if s.held[i] == 1 and box.has_point(s.centroid[i]):
			s.blow(i, Vector3.ZERO)


func _still() -> void:
	if options.has("pos"):
		_place(_vec(options["pos"]), _vec(options.get("at", "0,1.5,0")))
	await _wait(float(options.get("wait", "2.0")))
	_end("STILL_DONE")


## How loaded the building is as built: the bond nearest its limit (1 = it
## breaks). Used to tune Support.STRENGTH and the level.
func _check() -> void:
	var s := world.structure
	s.recheck()
	await _wait(0.3)
	print(
		"CHECK worst load %.2f of what a bond takes, solve %.2f ms" % [s.support.worst, s.solve_usec / 1000.0]
	)
	_end("CHECK_DONE")


func _end(tag: String) -> void:
	var s := world.structure
	print(
		(
			"%s standing=%d/%d pieces=%d most_awake=%d volume=%.2f/%.2f crumbs=%d"
			% [
				tag,
				s.held_count,
				s.count,
				s.pieces.live,
				_most_awake,
				s.standing_volume() + s.pieces.volume(),
				s.total_volume,
				s.total - s.count,
			]
		)
	)
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


## The point `text` stands for: "x,y,z", or "d" for the other brute's chest.
func _point(text: String) -> Vector3:
	return world.brute.global_position + Vector3.UP * 1.2 if text == "d" else _vec(text)


static func _vec(text: String) -> Vector3:
	var f := text.split_floats(",")
	return Vector3(f[0], f[1], f[2])
