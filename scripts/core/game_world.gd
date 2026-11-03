class_name GameWorld
extends Node3D
## Root of the game scene: loads the current level, wires structures,
## debris, player, blasts and all the juice (dust, shake, sound, slow-mo).

signal detonated(at: Vector3, params: BlastParams)

const SLOWMO_SCALE := 0.25  ## time scale for a full-charge blast
const SLOWMO_HOLD := 0.45  ## real seconds at full slow-down
const SLOWMO_RECOVER := 0.7  ## real seconds to ease back to 1x

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
var blasts_total := 0
var _slowmo_left := 0.0
var _slowmo_total := 0.0
var _slowmo_scale := SLOWMO_SCALE


static func of(node: Node) -> GameWorld:
	var n := node
	while n:
		if n is GameWorld:
			return n
		n = n.get_parent()
	return null


func _ready() -> void:
	Engine.time_scale = 1.0
	if OS.has_feature("web_ios") or OS.has_feature("web_android"):
		# Phones have 3x screens: render 3D at lower resolution, keep UI sharp.
		get_viewport().scaling_3d_scale = 0.6
	_load_level()
	build_structures()
	_connect_juice()
	if attract:
		_start_attract()


func _load_level() -> void:
	var path := level_path if level_path != "" else GameState.current_level
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Cannot load level %s" % path)
		return
	level = scene.instantiate() as Level
	level.name = "Level"
	structure_root.add_child(level)
	player.global_transform = level.player_start()
	player.reset_spawn()


func build_structures() -> void:
	if level == null:
		return
	for st in level.structures():
		structures.add_structure(st.global_transform, st.build_segments(), st.scored)
		st.visible = false


## Dust, chips, camera shake and sound for breaks and collapses.
func _connect_juice() -> void:
	structures.shattered.connect(
		func(at: Vector3, size: Vector3, kind: int) -> void:
			var r := size.length() * 0.5
			if dust:
				dust.puff(at, r, kind, int(6 + r * 8))
				dust.chips(at, r, kind, 4.0 + r * 2.0, int(6 + r * 10))
			Sfx.play_break(kind, at, r)
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
				dust.puff(at, r, Materials.Kind.CONCRETE, int(12 + count * 0.5))
				dust.puff(
					at + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * r,
					r * 0.7,
					Materials.Kind.CONCRETE,
					10
				)
				dust.chips(at, r, Materials.Kind.CONCRETE, 3.0 + speed * 0.5, int(10 + count * 0.3))
			Sfx.play("collapse", at, -10.0 + minf(mass / 400.0, 12.0))
			var cam := get_viewport().get_camera_3d() as CameraShake
			if cam:
				var d := cam.global_position.distance_to(at)
				var near := clampf(1.0 - d / 45.0, 0.0, 1.0)
				cam.add_trauma(clampf(mass / 4000.0, 0.1, 0.6) * near)
	)


## `travel`: the ball's velocity; the burst shoves standing things along it.
func detonate(at: Vector3, params: BlastParams, travel := Vector3.ZERO) -> GravityBlast:
	blasts_total += 1
	Sfx.play("implode", at, -6.0 + params.charge * 6.0, 1.15 - params.charge * 0.3)
	var blast := GravityBlast.new()
	blast.setup(self, params, at, travel)
	add_child(blast)
	var fx := BlastFx.new()
	fx.setup(params, at, blast)
	add_child(fx)
	var cam := get_viewport().get_camera_3d() as CameraShake
	if cam:
		var d := cam.global_position.distance_to(at)
		var near := clampf(1.0 - d / (params.radius * 4.0), 0.15, 1.0)
		cam.add_trauma(params.shake * 0.35 * near)
		blast.burst.connect(
			func() -> void:
				cam.add_trauma(params.shake * 0.8 * near)
				cam.kick_fov(4.0 + 8.0 * params.charge * near)
		)
	if params.slow_motion:
		# Full charge: deep slow-down. Medium charge: a lighter one.
		var depth := remap(params.charge, 0.6, 1.0, 0.5, SLOWMO_SCALE)
		blast.burst.connect(slow_motion.bind(depth))
	detonated.emit(at, params)
	return blast


func slow_motion(scale := SLOWMO_SCALE) -> void:
	_slowmo_scale = scale
	_slowmo_total = SLOWMO_HOLD + SLOWMO_RECOVER
	_slowmo_left = _slowmo_total


func _process(delta: float) -> void:
	if _slowmo_left > 0.0:
		var real := delta / maxf(Engine.time_scale, 0.001)
		_slowmo_left = maxf(_slowmo_left - real, 0.0)
		var elapsed := _slowmo_total - _slowmo_left
		if elapsed < SLOWMO_HOLD:
			Engine.time_scale = _slowmo_scale
		else:
			var k := (elapsed - SLOWMO_HOLD) / SLOWMO_RECOVER
			Engine.time_scale = lerpf(_slowmo_scale, 1.0, ease(clampf(k, 0.0, 1.0), 0.5))
		if _slowmo_left <= 0.0:
			Engine.time_scale = 1.0


func _start_attract() -> void:
	player.input_enabled = false
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
		await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(cam):
			return
		var dt := get_process_delta_time()
		t += dt
		var a := t * 0.06
		cam.global_position = Vector3(sin(a) * 30.0, 10.0, cos(a) * 30.0)
		cam.look_at(Vector3(0, 3, -6))
		next_blast -= dt
		if next_blast <= 0.0:
			next_blast = randf_range(3.5, 5.5)
			var target := _random_block_position()
			if target != Vector3.INF:
				detonate(target, BlastParams.from_charge(randf_range(0.45, 1.0)))
		# Rebuild the backdrop once it is mostly rubble, unless the player is
		# busy in a sub-menu (a reload would reset it).
		var busy := get_tree().get_first_node_in_group("menu_busy") != null
		if structures.destruction() > 0.6 and next_blast > 3.0 and not busy:
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
