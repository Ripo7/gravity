extends Node
## Scripted runs used by CI and for rendering previews:
##   --mode=showcase [--shots=DIR]  scripted blasts, optional screenshots
##   --mode=bench [--max=N]         body-count benchmark, prints BENCH lines
##   --mode=shot [--wait=S]         one screenshot of whatever is on screen
##   --mode=play --level=PATH --steps="g2@x,y,z;w1;p1@x,y,z;s0" [--from=x,y,z]
##        plays a level with scripted casts and prints the result (time,
##        stars, health): used to tune star times.

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


## Holds the cast button long enough for `tier`, aims at `target` first
## (not for the shield), releases. Optional screenshot while holding.
func _cast(power: int, tier: int, target := Vector3.INF, shot_name := "") -> void:
	var caster := player.power
	if target != Vector3.INF:
		await _aim(target, 0.4)
	caster.select(power)
	while not caster.is_ready(power):
		await get_tree().process_frame
	caster.begin()
	var hold := 0.05
	if tier == 1:
		hold = PowerDefs.TIER_TIMES.x + 0.05
	elif tier == 2:
		hold = PowerDefs.TIER_TIMES.y + 0.05
	await _wait(hold)
	if shot_name != "":
		await _shot(shot_name)
	caster.release()


func _showcase() -> void:
	await _wait(0.3)
	_place(Vector3(-2, 0.05, 14), Vector3(-4, 2.5, 0))
	await _wait(0.4)
	await _shot("01_arena")
	# 1: big singularity on the left tower.
	await _cast(PowerDefs.Power.GRAVITY, 2, Vector3(-12.5, 3.0, -8), "02_aim")
	await _wait(PowerDefs.GRAVITY_FUSE[2] * 0.6)
	await _shot("02_orb")
	var args: Array = await world.detonated
	var params: BlastParams = args[1]
	await _wait(params.pull_time * 0.6)
	await _shot("02_pull")
	await _wait(params.pull_time * 0.4 + 0.06)
	await _shot("02_burst")
	await _wait(2.4)
	await _shot("02_after")
	# 2: portal over the front wall.
	await _cast(PowerDefs.Power.PORTAL, 1, Vector3(0, 1.0, 2), "03_aim")
	await _wait(0.9)
	await _shot("03_portal")
	await _wait(0.8)
	await _shot("03_stones")
	await _wait(2.5)
	await _shot("03_after")
	# 3: shield, then a singularity behind it.
	_place(Vector3(10, 0.05, 6), Vector3(10, 1.5, -2))
	await _wait(0.2)
	await _cast(PowerDefs.Power.SHIELD, 1, Vector3(10, 1.5, -2), "04_aim")
	await _wait(0.5)
	await _shot("04_shield")
	await _cast(PowerDefs.Power.GRAVITY, 1, Vector3(13, 1.5, -10))
	await _wait(3.0)
	await _shot("04_after")
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


## Plays the current level with a scripted list of casts and reports the
## outcome. Steps (separated by ";"): g/p/s + size 0-2 [+ @x,y,z target],
## "w<seconds>" to wait, "m<x,y,z>" to walk (teleport) there.
func _play() -> void:
	var run := world.get_node_or_null("Run") as LevelRun
	if options.has("from"):
		player.global_position = _vec(options["from"])
	if options.has("god"):
		player.invulnerable = true
	await _wait(0.6)
	await _shot("00_start")
	var k := 0
	var codes := {"g": PowerDefs.Power.GRAVITY, "p": PowerDefs.Power.PORTAL, "s": PowerDefs.Power.SHIELD}
	for spec: String in String(options.get("steps", "")).split(";", false):
		if run and run.state != LevelRun.State.PLAY:
			break
		var kind := spec.substr(0, 1)
		if kind == "w":
			await _wait(float(spec.substr(1)))
			continue
		if kind == "m":
			player.global_position = _vec(spec.substr(1))
			continue
		var parts := spec.split("@")
		var tier := int(parts[0].substr(1, 1))
		var target := _vec(parts[1]) if parts.size() > 1 else Vector3.INF
		k += 1
		await _cast(codes[kind], tier, target)
		print(
			(
				"CAST %d %s t=%.1f destruction=%.3f hp=%d"
				% [k, spec, run.elapsed if run else 0.0, world.structures.destruction(), player.health]
			)
		)
		if k % 2 == 0:
			await _shot("%02d_cast" % k)
	if run and not run.level.is_sandbox():
		var waited := 0.0
		while run.state not in [LevelRun.State.RESULT] and waited < 40.0:
			await _wait(0.5)
			waited += 0.5
		await _wait(1.0)
		await _shot("99_result")
		print(
			(
				"RESULT cleared=%s stars=%d time=%.1f destruction=%.3f hp=%d"
				% [run.cleared, run.result_stars, run.elapsed, world.structures.destruction(), player.health]
			)
		)
	get_tree().quit()


## One screenshot from --pos=x,y,z looking at --at=x,y,z.
func _still() -> void:
	var p := _vec(options.get("pos", "0,0.05,15"))
	var t := _vec(options.get("at", "0,3,0"))
	_place(p, t)
	if options.has("hold"):
		# --hold=POWER:TIER shows the preview, e.g. --hold=1:2
		var ht := String(options["hold"]).split(":")
		player.power.select(int(ht[0]))
		player.power.begin()
		player.power.held_time = [0.0, 0.4, 0.9][int(ht[1])]
	if options.has("touchdemo"):
		_touch_demo()
	if options.has("blast"):
		var params := BlastParams.from_charge(float(options["blast"]))
		await _wait(0.2)
		world.detonate(t, params)
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
