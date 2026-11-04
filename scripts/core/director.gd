extends Node
## Scripted runs used by CI and for rendering previews:
##   --mode=showcase [--shots=DIR]  scripted blasts, optional screenshots
##   --mode=bench [--max=N]         body-count benchmark, prints BENCH lines
##   --mode=shot [--wait=S]         one screenshot of whatever is on screen
##   --mode=play --steps="v@x,y,z;w1;s" [--from=x,y,z] [--god]
##        plays with scripted casts and prints destruction, health, deaths.

var options := {}
var world: GameWorld
var player: Player
var _shot_dir := ""
var _label: Label


func _ready() -> void:
	world = get_parent() as GameWorld
	player = world.player
	_shot_dir = options.get("shots", "")
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	if options.get("mode", "") == "probe":
		_probe()
		return
	if options.get("mode", "") == "shot":
		await _wait(float(options.get("wait", "2.0")))
		await _shot(options.get("name", "shot"))
		get_tree().quit()
		return
	player.input_enabled = false
	player.power.auto_input = true
	if options.has("prof"):
		_profile()
	match options.get("mode", ""):
		"showcase":
			_showcase()
		"bench":
			_bench()
		"still":
			_still()
		"play":
			_play()


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


## Aims at `target` (not needed for the shield), waits for the cooldown,
## casts. Optional screenshot right before casting.
func _cast(power: int, target := Vector3.INF, shot_name := "") -> void:
	var caster := player.power
	if target != Vector3.INF:
		await _aim(target, 0.4)
	while not caster.is_ready(power):
		await get_tree().process_frame
	if shot_name != "":
		await _shot(shot_name)
	caster.cast_now(power)


func _showcase() -> void:
	await _wait(0.3)
	_place(Vector3(0, 0.05, 34), Vector3(0, 5, 0))
	await _wait(0.4)
	await _shot("01_start")
	# 1: black hole in the south avenue, between the buildings.
	await _cast(PowerDefs.Power.VORTEX, Vector3(0, 5, 16), "02_aim")
	await _wait(1.5)
	await _shot("02_vortex")
	await _wait(2.5)
	await _shot("02_spin")
	await _wait(4.0)
	await _shot("02_after")
	# 2: shield up on the boulevard, then a black hole tears the building
	# ahead apart.
	_place(Vector3(2, 0.05, 2), Vector3(10, 4, -12))
	await _wait(0.3)
	await _cast(PowerDefs.Power.SHIELD)
	await _wait(0.5)
	await _shot("03_shield")
	await _cast(PowerDefs.Power.VORTEX, Vector3(9, 4, -11))
	await _wait(2.5)
	await _shot("03_storm")
	await _wait(4.0)
	await _shot("03_after")
	# 3: on the north walkway, shield, black hole in the far block.
	_place(Vector3(0, 6.5, -12.5), Vector3(-10, 8, -31))
	await _wait(0.3)
	await _shot("04_walkway")
	await _cast(PowerDefs.Power.SHIELD)
	await _wait(0.6)
	await _shot("04_shield")
	await _cast(PowerDefs.Power.VORTEX, Vector3(-10, 8, -31))
	await _wait(3.0)
	await _shot("04_towers")
	await _wait(5.0)
	_place(Vector3(0, 0.05, 40), Vector3(0, 6, 0))
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


## Plays the level with a scripted list of steps and reports what happened.
## Steps (separated by ";"): v/p/s [+ @x,y,z target], "w<seconds>" to wait,
## "m<x,y,z>" to teleport there.
func _play() -> void:
	if options.has("from"):
		player.global_position = _vec(options["from"])
	if options.has("god"):
		player.invulnerable = true
	var run := world.get_node_or_null("Run") as LevelRun
	await _wait(0.6)
	await _shot("00_start")
	var k := 0
	var codes := {"v": PowerDefs.Power.VORTEX, "s": PowerDefs.Power.SHIELD}
	for spec: String in String(options.get("steps", "")).split(";", false):
		var kind := spec.substr(0, 1)
		if kind == "w":
			await _wait(float(spec.substr(1)))
			continue
		if kind == "m":
			player.global_position = _vec(spec.substr(1))
			continue
		var parts := spec.split("@")
		var target := _vec(parts[1]) if parts.size() > 1 else Vector3.INF
		k += 1
		await _cast(codes[kind], target)
		print(
			(
				"CAST %d %s destruction=%.3f hp=%d deaths=%d"
				% [k, spec, world.structures.destruction(), player.health, run.deaths if run else 0]
			)
		)
		if k % 2 == 0:
			await _shot("%02d_cast" % k)
	print(
		(
			"END destruction=%.3f hp=%d deaths=%d"
			% [world.structures.destruction(), player.health, run.deaths if run else 0]
		)
	)
	get_tree().quit()


## One screenshot from --pos=x,y,z looking at --at=x,y,z.
func _still() -> void:
	var p := _vec(options.get("pos", "0,0.05,15"))
	var t := _vec(options.get("at", "0,3,0"))
	_place(p, t)
	if options.has("touchdemo"):
		_touch_demo()
	if options.has("vortex"):
		await _wait(0.2)
		world.cast_vortex(t)
	if options.has("dust"):
		await _wait(0.1)
		world.dust.roll(_vec(options["dust"]), 4.0, 1.0)
		world.dust.puff(_vec(options["dust"]) + Vector3(-6, 2, 0), 1.0, Materials.Kind.CONCRETE, 20)
	if options.has("collapse"):
		# Knock out the ground floor of the building at --collapse=x,z.
		var at := _vec(options["collapse"] + ",0")
		at = Vector3(at.x, 0, at.y)
		var s := world.structures
		for i in s.segment_count():
			var bp := s.transform_of(i).origin
			if s.is_alive(i) and bp.y < 2.9 and absf(bp.x - at.x) < 6.5 and absf(bp.z - at.z) < 6.5:
				s.break_segment(i)
	if options.has("shieldat"):
		# A shield seen from outside: --shieldat=x,y,z --shieldyaw=deg
		var yaw := deg_to_rad(float(options.get("shieldyaw", "0")))
		world.cast_shield(Transform3D(Basis(Vector3.UP, yaw), _vec(options["shieldat"])))
	await _wait(float(options.get("wait", "0.5")))
	await _shot(options.get("name", "still"))
	get_tree().quit()


## Fakes a thumb on the stick and one on the charge button (for screenshots).
func _touch_demo() -> void:
	player.power.auto_input = false
	var c: TouchControls
	for n in world.find_children("*", "Control", true, false):
		if n is TouchControls:
			c = n
	if c == null:
		return
	var stick := InputEventScreenTouch.new()
	stick.index = 0
	stick.pressed = true
	stick.position = Vector2(c.size.y * 0.26, c.size.y * 0.74)
	c._on_touch(stick)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = stick.position + Vector2(c.size.y * 0.04, -c.size.y * 0.1)
	c._on_drag(drag)
	var cast := InputEventScreenTouch.new()
	cast.index = 1
	cast.pressed = true
	cast.position = c.charge_center()
	c._on_touch(cast)


static func _vec(s: String) -> Vector3:
	var f := s.split_floats(",")
	return Vector3(f[0], f[1], f[2])


func _bench() -> void:
	var debris := world.debris
	debris.retire_min_age = INF  # measure raw body counts, no soft budget
	var step := int(options.get("step", "150"))
	var limit := mini(int(options.get("max", "3000")), debris.capacity)
	# A pile in the north avenue, between the buildings.
	_place(Vector3(0, 0.05, -12), Vector3(0, 1, -30))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var over := 0
	await _wait(1.0)
	_report("BENCH_START capacity=%d web=%s" % [debris.capacity, OS.has_feature("web")])
	while debris.active_count + step <= limit:
		for k in step:
			var n := debris.active_count
			var x := float(n % 10) * 1.1 - 5.0 + rng.randf_range(-0.2, 0.2)
			var z := -30.0 + float(floori(n / 10.0) % 12) * 1.1 - 6.0
			var y := 1.5 + float(floori(n / 120.0)) * 1.2 + rng.randf_range(0.0, 0.5)
			var s := Vector3(rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7))
			debris.spawn(
				Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf(), 0)), Vector3(x, y, z)), s
			)
		var falling := await _measure(2.0)
		await _wait(2.0)
		var settled := await _measure(1.0)
		world.cast_vortex(Vector3(0, 1.0, -30))
		await _wait(PowerDefs.VORTEX_SPINUP + 1.0)
		var blast := await _measure(2.0)
		await _wait(PowerDefs.VORTEX_DURATION)
		_report(
			(
				"BENCH bodies=%d  physics ms: falling %.1f  settled %.1f  vortex %.1f  |  fps %d"
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


## --prof: once a second, average frame costs and live piece counts.
func _profile() -> void:
	var proc := 0.0
	var phys := 0.0
	var worst := 0.0
	var n := 0
	var t := 0.0
	while is_inside_tree():
		await get_tree().process_frame
		var p := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var f := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += p
		phys += f
		worst = maxf(worst, p + f)
		n += 1
		t += get_process_delta_time()
		if t >= 1.0:
			var chips := world.dust.chip_system.active if world.dust else 0
			print(
				(
					"PROF process %.1f  physics %.1f  worst %.1f ms  debris %d (awake %d, frozen %d)  chips %d"
					% [
						proc / n,
						phys / n,
						worst,
						world.debris.active_count,
						world.debris.awake_count,
						world.debris.frozen_count,
						chips,
					]
				)
			)
			proc = 0.0
			phys = 0.0
			worst = 0.0
			n = 0
			t = 0.0


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
