extends Node
## Scripted runs used by CI and for rendering previews:
##   --mode=showcase [--shots=DIR]  scripted blasts, optional screenshots
##   --mode=bench [--max=N]         body-count benchmark, prints BENCH lines

var options := {}
var world: GameWorld
var player: Player
var _shot_dir := ""
var _label: Label


func _ready() -> void:
	world = get_parent() as GameWorld
	player = world.player
	if options.get("mode", "") == "probe":
		_probe()
		return
	player.input_enabled = false
	player.power.auto_input = true
	_shot_dir = options.get("shots", "")
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	match options.get("mode", ""):
		"showcase":
			_showcase()
		"bench":
			_bench()
		"still":
			_still()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true, false).timeout


func _shot(name: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir.path_join(name + ".png"))
	print("SHOT ", name)


func _place(at: Vector3, target: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.external_velocity = Vector3.ZERO
	_aim_now(target)


func _aim_now(target: Vector3) -> void:
	var yp := _yaw_pitch(target)
	player.rotation.y = yp.x
	player.head.rotation.x = yp.y


func _aim(target: Vector3, seconds: float) -> void:
	var yp := _yaw_pitch(target)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	tw.tween_property(player, "rotation:y", yp.x, seconds)
	tw.tween_property(player.head, "rotation:x", yp.y, seconds)
	await tw.finished


func _yaw_pitch(target: Vector3) -> Vector2:
	var eye := player.global_position + Vector3(0, 1.6, 0)
	var d := target - eye
	var yaw := atan2(-d.x, -d.z)
	# Unwrap so tweens take the short way round.
	yaw = player.rotation.y + wrapf(yaw - player.rotation.y, -PI, PI)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	return Vector2(yaw, pitch)


## Charge for `seconds`, release, and return after the burst settles a bit.
func _throw(seconds: float, shot_prefix := "") -> void:
	var hand := player.power
	hand.begin_charge()
	await _wait(seconds * 0.75)
	if shot_prefix != "":
		await _shot(shot_prefix + "_charging")
	await _wait(seconds * 0.25)
	hand.release()
	var args: Array = await world.detonated
	var params: BlastParams = args[1]
	if shot_prefix != "":
		await _wait(params.pull_time * 0.6)
		await _shot(shot_prefix + "_pull")
		await _wait(params.pull_time * 0.4 + 0.06)
		await _shot(shot_prefix + "_burst")
	else:
		await _wait(params.pull_time + 0.1)


func _showcase() -> void:
	await _wait(0.3)
	_place(Vector3(-2, 0.05, 14), Vector3(-4, 2.5, 0))
	await _wait(0.4)
	await _shot("01_arena")
	# 1: big blast into the left tower.
	await _aim(Vector3(-12.5, 4.5, -8), 0.6)
	await _throw(1.7, "02_tower")
	await _wait(2.4)
	await _shot("02_tower_after")
	# 2: medium blast into the front wall.
	await _aim(Vector3(1.5, 1.6, 2), 0.6)
	await _throw(0.9, "03_wall")
	await _wait(2.0)
	await _shot("03_wall_after")
	# 3: walk through the gap and hit the colonnade.
	_place(Vector3(2, 0.05, -4), Vector3(0, 2.5, -16))
	await _wait(0.3)
	await _throw(1.7, "04_colonnade")
	await _wait(2.5)
	await _shot("04_colonnade_after")
	# 4: overview.
	_place(Vector3(10, 0.05, 16), Vector3(-6, 1.6, -10))
	await _wait(0.5)
	await _shot("05_overview")
	print("SHOWCASE_DONE pieces=%d standing=%d" % [world.debris.active_count, world.structures.alive_count])
	get_tree().quit()


## Prints the player state twice a second; input stays live (input checks).
func _probe() -> void:
	while true:
		await _wait(0.5)
		var p := player.global_position
		print(
			(
				"PROBE pos=%.2f,%.2f,%.2f fwd=%s floor=%s mouse=%d"
				% [
					p.x,
					p.y,
					p.z,
					Input.is_action_pressed("move_forward"),
					player.is_on_floor(),
					Input.mouse_mode,
				]
			)
		)


## One screenshot from --pos=x,y,z looking at --at=x,y,z.
func _still() -> void:
	var p := _vec(options.get("pos", "0,0.05,15"))
	var t := _vec(options.get("at", "0,3,0"))
	_place(p, t)
	if options.has("charge"):
		player.power.begin_charge()
		player.power.charge = float(options["charge"])
	if options.has("blast"):
		var params := BlastParams.from_charge(float(options["blast"]))
		await _wait(0.2)
		world.detonate(t, params)
	await _wait(float(options.get("wait", "0.5")))
	await _shot(options.get("name", "still"))
	get_tree().quit()


static func _vec(s: String) -> Vector3:
	var f := s.split_floats(",")
	return Vector3(f[0], f[1], f[2])


func _bench() -> void:
	var debris := world.debris
	var step := int(options.get("step", "150"))
	var limit := mini(int(options.get("max", "3000")), debris.capacity)
	_place(Vector3(0, 0.05, 50), Vector3(0, 1, 30))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var over := 0
	await _wait(1.0)
	_report("BENCH_START capacity=%d web=%s" % [debris.capacity, OS.has_feature("web")])
	while debris.active_count + step <= limit:
		for k in step:
			var n := debris.active_count
			var x := float(n % 12) * 1.1 - 6.0 + rng.randf_range(-0.2, 0.2)
			var z := 30.0 + float(floori(n / 12.0) % 12) * 1.1 - 6.0
			var y := 1.5 + float(floori(n / 144.0)) * 1.2 + rng.randf_range(0.0, 0.5)
			var s := Vector3(rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7))
			debris.spawn(
				Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf(), 0)), Vector3(x, y, z)), s
			)
		var falling := await _measure(2.0)
		await _wait(2.0)
		var settled := await _measure(1.0)
		world.detonate(Vector3(0, 1.0, 30), BlastParams.from_charge(1.0))
		await _wait(0.4)
		var blast := await _measure(1.5)
		await _wait(1.5)
		_report(
			(
				"BENCH bodies=%d  physics ms: falling %.1f  settled %.1f  blast %.1f  |  fps %d"
				% [debris.active_count, falling.x, settled.x, blast.x, blast.y]
			)
		)
		over = over + 1 if blast.x > 16.6 else 0
		if over >= 2:
			break
	_report("BENCH_DONE")
	if not OS.has_feature("web"):
		get_tree().quit()


## Average physics time (ms) over `seconds` of simulated time, and render fps.
## Counted in physics frames so a slow renderer does not skew the physics cost.
func _measure(seconds: float) -> Vector2:
	var total := 0.0
	var frames := int(seconds * Engine.physics_ticks_per_second)
	for i in frames:
		await get_tree().physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return Vector2(total / maxf(frames, 1), Engine.get_frames_per_second())


func _report(text: String) -> void:
	print(text)
	if _label == null:
		var layer := CanvasLayer.new()
		layer.layer = 10
		add_child(layer)
		_label = Label.new()
		_label.position = Vector2(20, 120)
		_label.add_theme_font_size_override("font_size", 18)
		_label.add_theme_color_override("font_color", Color(0.2, 0.1, 0.35))
		layer.add_child(_label)
	_label.text += text + "\n"
