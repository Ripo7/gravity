class_name Director
extends Node
## Scripted runs, for clips and measurements:
##   --mode=play --steps="s1.5,0.05,-4.55,1.5,1,-6;h;w0.5;h" [--from=x,y,z]
##        steps separated by ";": "w<seconds>" wait, "m<x,y,z>" go there,
##        "s<x,y,z>,<x,y,z>" stand there, facing the second point,
##        "a@x,y,z" look there, "f<seconds>" run forward, "r<seconds>"
##        sprint forward, "p<x>,<y>,<seconds>[,1]" push the stick (y -1 is
##        forward; 1: sprint), "j" jump, "h" punch, "d" both fists down,
##        "t<degrees>,<seconds>" turn the camera to the left,
##        "c<share>" set how fast things fall (see Rubble.fall).
##   --mode=still [--pos=x,y,z --at=x,y,z --wait=S]   just look
##   --mode=mesure   what the picture costs here while the bench is broken
##        (in a browser: index.html?mode=mesure), see `_measure`.
## --prof prints the cost of the physics once a second (PROF lines) and
## how the steps are spread at the end (STEPS).

## ms: a physics step longer than this on a desktop is a hitch on a phone.
const SLOW_STEP := 6.0
## The measure: the bench is looked at whole for STILL s, then a piece is
## broken every BETWEEN s and what comes down is given SETTLE s, then the
## rubble is looked at for STILL s; ROUNDS times over.
const STILL := 5.0
const BETWEEN := 0.6
const SETTLE := 6.0
const ROUNDS := 2

var options := {}
var world: Main
var player: Player
var _most_awake := 0


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
		"mesure":
			_measure()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true, false).timeout


func _place(at: Vector3, target: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.look_at_point(target)
	player.facing = player.yaw


## Puts the brute at `at`, its body turned to `target`, the camera behind
## it.
func _face(at: Vector3, target: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.facing = atan2(at.x - target.x, at.z - target.z)
	player.look(Vector2(angle_difference(player.yaw, player.facing), 0.0))


func _profile() -> void:
	world.clock.keep_history = true
	while true:
		await _wait(1.0)
		var loose := world.structure.rubble
		_most_awake = maxi(_most_awake, loose.awake)
		print(
			(
				"PROF physics %.2f ms/step (worst %.2f)  loose %d (awake %d)"
				% [world.clock.avg_ms, world.clock.worst_ms, loose.live, loose.awake]
			)
		)


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
		elif kind == "s":
			var f := spec.substr(1).split_floats(",")
			_face(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]))
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
		elif kind == "d":
			player.touch_hammer = true
		elif kind == "c":
			world.fall = float(spec.substr(1))
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


## Tells what the picture costs on this machine while the bench is broken.
## Nobody plays: the brute stands where it starts, looking at the bench,
## and the same thing happens every time. Three stretches: the bench whole;
## every piece broken, one after the other; the rubble at rest. For each,
## the frames a second over the stretch and in its slowest second, on the
## screen (to be photographed) and as MEASURE lines. Then all of it once
## more: a phone changes pace by itself, and only what both rounds agree on
## counts.
func _measure() -> void:
	var board := Label.new()
	board.position = Vector2(24, 110)
	board.add_theme_font_size_override("font_size", 24)
	board.add_theme_color_override("font_outline_color", Color.BLACK)
	board.add_theme_constant_override("outline_size", 8)
	var layer := CanvasLayer.new()
	layer.add_child(board)
	world.add_child(layer)
	var view := get_viewport().get_visible_rect().size
	var lines: Array[String] = ["Mesure en cours... (%d x %d, chute %.2f)" % [view.x, view.y, world.fall]]
	board.text = lines[0]
	await _wait(2.0)
	for lap in ROUNDS:
		if lap > 0:
			world.rebuild()
			await _wait(1.0)
		var broken := world.structure.pieces * BETWEEN + SETTLE
		var stretches: Array[Array] = [["banc entier", STILL], ["tout casse", broken], ["gravats", STILL]]
		for stretch in stretches:
			if stretch[0] == "tout casse":
				_demolish()
			var rate: Vector2 = await _rate(stretch[1])
			lines.append("Passe %d, %s : %.0f i/s (au pire %.0f)" % [lap + 1, stretch[0], rate.x, rate.y])
			print("MEASURE round %d %s: %.1f (worst second %.1f)" % [lap + 1, stretch[0], rate.x, rate.y])
			board.text = "\n".join(lines)
	lines[0] = "Mesure finie (%d x %d, chute %.2f) : fais une capture." % [view.x, view.y, world.fall]
	board.text = "\n".join(lines)
	print("MEASURE_DONE")
	if DisplayServer.get_name() == "headless":
		get_tree().quit()


## Breaks every piece of the bench, one every BETWEEN s, as the last blow
## it can take would.
func _demolish() -> void:
	var s := world.structure
	for p in s.pieces:
		if is_instance_valid(s) and s.state[p] != Structure.BROKEN:
			s.hit(p, s.strength[p], Vector3.FORWARD)
		await _wait(BETWEEN)


## The frames a second drawn over `seconds` (x), and in the slowest second
## of them (y).
func _rate(seconds: float) -> Vector2:
	var drawn := Engine.get_frames_drawn()
	var began := Time.get_ticks_usec()
	var worst := INF
	var left := seconds
	while left > 0.0:
		var before := Engine.get_frames_drawn()
		var from := Time.get_ticks_usec()
		await _wait(minf(1.0, left))
		left -= 1.0
		worst = minf(worst, (Engine.get_frames_drawn() - before) / ((Time.get_ticks_usec() - from) / 1e6))
	return Vector2((Engine.get_frames_drawn() - drawn) / ((Time.get_ticks_usec() - began) / 1e6), worst)


func _end(tag: String) -> void:
	var s := world.structure
	# (Marked: what still stands but has taken something, cracked or bent.)
	var marked := 0
	for p in s.pieces:
		if s.state[p] == Structure.STANDS and s.harm[p] > 0.0:
			marked += 1
	print(
		(
			"%s at=%s standing=%d/%d marked=%d loose=%d most_awake=%d"
			% [
				tag,
				player.global_position.snappedf(0.01),
				s.standing_count,
				s.pieces,
				marked,
				s.rubble.live,
				_most_awake
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


static func _vec(text: String) -> Vector3:
	var f := text.split_floats(",")
	return Vector3(f[0], f[1], f[2])
