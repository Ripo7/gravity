class_name GameWorld
extends Node3D
## Root of the game scene: loads the current level, wires structures,
## debris, player, blasts and all the juice (dust, shake, sound). No slow
## motion and no freeze frames: the game always runs at its own pace.

signal vortex_opened(vortex: Vortex)

@export var structures: StructureSet
@export var debris: DebrisSystem
@export var player: Player
@export var structure_root: Node3D
@export var dust: DustSystem
## Overrides GameState.current_level (tests, tools).
@export_file("*.tscn") var level_path := ""
## Menu backdrop: no player control, an orbiting camera and automatic blasts.
@export var attract := false

var level: Level
## Path of the level scene that was loaded.
var level_file := ""
var blasts_total := 0
## True cost of a physics step (HUD stats, benchmarks).
var physics_clock: PhysicsClock


static func of(node: Node) -> GameWorld:
	var n := node
	while n:
		if n is GameWorld:
			return n
		n = n.get_parent()
	return null


func _ready() -> void:
	Engine.time_scale = 1.0
	physics_clock = PhysicsClock.new()
	physics_clock.name = "PhysicsClock"
	add_child(physics_clock)
	_load_level()
	build_structures()
	_connect_juice()
	if attract:
		_start_attract()


func _load_level() -> void:
	var path := level_path if level_path != "" else GameState.current_level
	level_file = path
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Cannot load level %s" % path)
		return
	level = scene.instantiate() as Level
	level.name = "Level"
	structure_root.add_child(level)
	player.global_transform = level.player_start()
	player.reset_spawn()
	var kind := "menu" if attract else "level"
	print("SCENE %s %s" % [kind, level.title])


func build_structures() -> void:
	if level == null:
		return
	var footprints: Array[Vector4] = []
	for st in level.structures():
		var segments := st.build_segments()
		structures.add_structure(st.global_transform, segments)
		footprints.append(_footprint(st.global_transform, segments))
		st.visible = false
	structures.link_anchors()
	_dress_floor(footprints)


## Ground-floor extent of a structure: (min x, min z, max x, max z).
static func _footprint(origin: Transform3D, segments: Array[Dictionary]) -> Vector4:
	var r := Vector4(INF, INF, -INF, -INF)
	for seg in segments:
		var size: Vector3 = seg["size"]
		var box := (origin * (seg["local"] as Transform3D)) * AABB(-size * 0.5, size)
		if box.position.y < 0.3:
			r = Vector4(
				minf(r.x, box.position.x),
				minf(r.y, box.position.z),
				maxf(r.z, box.end.x),
				maxf(r.w, box.end.z)
			)
	return r


## Tells the floor shader where the square ends (the arena) and where the
## buildings stand (a travertine kerb round each; the band grid starts at the
## front of the largest).
func _dress_floor(footprints: Array[Vector4]) -> void:
	var mesh := get_node_or_null("Floor/Mesh") as MeshInstance3D
	var mat := mesh.get_surface_override_material(0) as ShaderMaterial if mesh else null
	if mat == null:
		return
	var half := 1e6
	for child in level.get_children():
		if child is Arena:
			half = (child as Arena).inner
	var rects: Array[Vector4] = []
	var origin := Vector2.ZERO
	var biggest := 0.0
	for r in footprints:
		if r.x > r.z or rects.size() == 4:
			continue
		rects.append(r)
		if (r.z - r.x) * (r.w - r.y) > biggest:
			biggest = (r.z - r.x) * (r.w - r.y)
			origin = Vector2((r.x + r.z) * 0.5, r.w)
	var count := rects.size()
	rects.resize(4)
	mat.set_shader_parameter("square_half", half)
	mat.set_shader_parameter("grid_origin", origin)
	mat.set_shader_parameter("plinths", rects)
	mat.set_shader_parameter("plinth_count", count)


## Dust, chips, camera shake and sound for breaks and collapses.
func _connect_juice() -> void:
	if dust:
		dust.structures = structures
		structures.dust = dust
		debris.chips = dust.chip_system
	var rebar := RebarSystem.new()
	add_child(rebar)
	structures.rebar = rebar
	var aq := AdaptiveQuality.new()
	aq.world = self
	add_child(aq)
	if dust:
		dust.light_from(get_node_or_null("Sun") as DirectionalLight3D)
		var floor_mesh := get_node_or_null("Floor/Mesh") as MeshInstance3D
		if floor_mesh:
			dust.use_floor(floor_mesh.get_surface_override_material(0) as ShaderMaterial)
	structures.shattered.connect(
		func(at: Vector3, size: Vector3, kind: int) -> void:
			var r := size.length() * 0.5
			if dust and kind == Materials.Kind.GLASS:
				# A pane bursts into glittering shards.
				var area := size.x * size.y + size.y * size.z + size.x * size.z
				dust.chips_box(at, size, kind, clampi(int(area * 10.0), 10, 40), 3.5)
			elif dust:
				dust.puff(at, r, kind, int(6 + r * 8))
				# Gravel scales with the volume that broke.
				var vol := size.x * size.y * size.z
				dust.chips_box(at, size, kind, clampi(int(8 + vol * 30.0), 8, 40), 3.0 + r * 2.0)
			Sfx.play_break(kind, at, r)
	)
	debris.piece_broke.connect(
		func(at: Vector3, size: Vector3, kind: int, speed: float) -> void:
			var r := size.length() * 0.5
			if dust:
				dust.puff(at, r, kind, int(6 + r * 6))
				dust.chips_box(at, size, kind, clampi(int(6 + speed), 6, 24), 2.5)
			Sfx.play_break(kind, at, r)
	)
	structures.about_to_fail.connect(
		func(at: Vector3, count: int) -> void:
			# It creaks, sheds a little dust and gravel, and holds a moment.
			Sfx.play("creak", at, -2.0 + minf(count, 120) * 0.05, 0.8)
			if dust:
				dust.puff(at, 1.5, Materials.Kind.CONCRETE, 8)
				dust.chips(at, 2.0, Materials.Kind.CONCRETE, 1.0, 14)
			var cam := get_viewport().get_camera_3d() as CameraShake
			if cam:
				var d := cam.global_position.distance_to(at)
				cam.add_trauma(0.12 * clampf(1.0 - d / 40.0, 0.0, 1.0))
	)
	structures.floor_crushed.connect(
		func(at: Vector3, count: int, speed: float) -> void:
			# The storey crushed flat pushes its air out sideways, through
			# the windows: jets of dust all round it.
			if dust:
				var r := clampf(sqrt(float(count)) * 0.9, 2.5, 9.0)
				var jets := int(Quality.pick(4, 6, 8))
				var turn := randf() * TAU
				for k in jets:
					var a := turn + TAU * k / jets
					var out := Vector3(cos(a), 0.0, sin(a))
					dust.jet(
						at + out * r + Vector3.UP * 0.8, out, clampf(r * 0.35, 1.2, 2.6), 6.0 + speed * 0.4
					)
	)
	structures.cluster_released.connect(
		func(at: Vector3, count: int, toppled: bool) -> void:
			if toppled or count > 20:
				Sfx.play("creak", at, -4.0 + minf(count, 60) * 0.1)
	)
	structures.cluster_impact.connect(
		func(at: Vector3, mass: float, speed: float, count: int) -> void:
			var r := clampf(1.0 + count * 0.04, 1.0, 5.0)
			if dust:
				# Big pieces of building landing raise a rolling wall of dust
				# and leave a veil over the rubble.
				var strength := clampf(mass / 20000.0, 0.2, 1.0)
				dust.roll(at, r * 1.2, strength)
				if count > 12:
					dust.haze(at, r * 1.5)
				dust.chips(at, r, Materials.Kind.CONCRETE, 3.0 + speed * 0.5, int(10 + count * 0.3))
			Sfx.play("collapse", at, -10.0 + minf(mass / 400.0, 12.0))
			if count >= 15 and not attract:
				Sfx.duck(-9.0, 3.5)  # the music gives way to the rumble
			var cam := get_viewport().get_camera_3d() as CameraShake
			if cam:
				var d := cam.global_position.distance_to(at)
				var near := clampf(1.0 - d / 45.0, 0.0, 1.0)
				cam.add_trauma(clampf(mass / 4000.0, 0.1, 0.6) * near)
	)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- Powers --------------------------------------------------------------------


func cast_vortex(at: Vector3) -> Vortex:
	# The ball floats: never half buried in the floor it was aimed at.
	var lift := PowerDefs.VORTEX_CORE + 0.8
	var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * lift)
	down.exclude = [player.get_rid()] if player else []
	var hit := get_world_3d().direct_space_state.intersect_ray(down)
	if not hit.is_empty():
		at.y = maxf(at.y, (hit["position"] as Vector3).y + lift)
	var v := Vortex.new()
	v.setup(self, at)
	add_child(v)
	var cam := get_viewport().get_camera_3d() as CameraShake
	if cam:
		cam.add_trauma(0.35 * clampf(1.0 - cam.global_position.distance_to(at) / 60.0, 0.1, 1.0))
	vortex_opened.emit(v)
	return v


func cast_shield(base: Transform3D) -> IceShield:
	var shield := IceShield.new()
	shield.setup(self, base)
	add_child(shield)
	return shield


func _start_attract() -> void:
	player.input_enabled = false
	player.invulnerable = true
	player.power.auto_input = true
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := CameraShake.new()
	cam.base_fov = 60.0
	add_child(cam)
	cam.make_current()
	var t := 0.0
	var next_blast := 2.5
	while is_inside_tree():
		var tree := get_tree()
		await tree.process_frame
		if not is_inside_tree() or not is_instance_valid(cam):
			return
		var dt := get_process_delta_time()
		t += dt
		var a := t * 0.05
		cam.global_position = Vector3(-4.0 + sin(a) * 50.0, 20.0, -8.0 + cos(a) * 50.0)
		cam.look_at(Vector3(-4, 9, -8))
		next_blast -= dt
		if next_blast <= 0.0:
			next_blast = randf_range(3.5, 5.5)
			var target := _random_block_position()
			if target != Vector3.INF:
				cast_vortex(target)
		# Rebuild the backdrop once it is mostly rubble.
		if structures.standing_fraction() < 0.5 and next_blast > 3.0:
			reset()
			return


func _random_block_position() -> Vector3:
	var n := structures.segment_count()
	for tries in 20:
		var i := randi() % n
		if structures.is_alive(i):
			return structures.transform_of(i).origin
	return Vector3.INF


func reset() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()
