class_name Main
extends Node3D
## The game, in greybox, walked in first person with a shock wave that
## breaks things (see Structure) and an orb that swallows the debris (see
## Orb). Two levels: the course, where the point is to get to the far end
## (see Course), and the house, a sandbox to take apart.
## Textures: Kenney's prototype textures (CC0).

const TEXTURES := "res://addons/kenney_prototype_textures/"

## The level every scene started from now on builds: "course" or "house".
## Empty: as asked on the command line (--level=), else the course, or the
## house for scripted runs (--mode=).
static var next_level := ""

var structure: Structure
var player: Player
var dust: Dust
var chips: Chips
var clock: PhysicsClock
var hud: Hud
var orb: Orb  ## the one held open, if any
var level := ""
var course: Course  ## the course, when that is the level
var sun: DirectionalLight3D
var air: Environment
## Where the house stands.
var house_at := Transform3D(Basis(), Vector3(0, 0, -4))
## Milliseconds it took to cut and bond the house.
var build_ms := 0.0


func _ready() -> void:
	clock = PhysicsClock.new()
	add_child(clock)
	_build_world()
	structure = Structure.new()
	structure.most_crumbs = int(Quality.pick(250, 450, 800))
	add_child(structure)
	var options: Dictionary = get_node("/root/Launch").options
	level = next_level
	if level == "":
		level = options.get("level", "house" if options.has("mode") else "course")
	var t := Time.get_ticks_usec()
	if level == "course":
		course = Course.new()
		add_child(course)
		course.build(structure)
		# The sun down the corridor, from behind you: its floor and what
		# faces you are lit, not in the shadow of its sides.
		sun.rotation_degrees = Vector3(-58, 10, 0)
		air.ambient_light_energy = 0.65
	else:
		House.build(structure, house_at)
	structure.build()
	# (In the course a plug is held by nothing: it has to come loose now,
	# not at the first shock wave.)
	structure.recheck()
	build_ms = (Time.get_ticks_usec() - t) / 1000.0
	dust = Dust.new()
	add_child(dust)
	chips = Chips.new()
	add_child(chips)
	structure.released.connect(_on_released)
	player = Player.new()
	player.pieces = structure.pieces
	add_child(player)
	if course != null:
		player.global_transform = course.start
		course.watch(player)
	else:
		player.global_position = house_at * Vector3(0, 0.05, 15)
	player.fired.connect(cast_shockwave)
	player.gathering_changed.connect(
		func(on: bool) -> void:
			if on:
				start_orb()
			else:
				drop_orb()
	)
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = self
	ui.add_child(hud)
	hud.rebuild_pressed.connect(rebuild)
	hud.switch_pressed.connect(switch_level)
	# (--touch: the thumb controls on a desktop, to look at them.)
	if TouchControls.should_show() or options.has("touch"):
		var touch := TouchControls.new()
		touch.player = player
		ui.add_child(touch)
	print(
		(
			"BUILD %s shards=%d bonds=%d vertices=%d in %.0f ms (tier %d)"
			% [
				level,
				structure.count,
				structure.bond_a.size(),
				structure.mesh.vertex_count,
				build_ms,
				Quality.tier()
			]
		)
	)
	if options.has("mode"):
		var director := Director.new()
		director.options = options
		add_child(director)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rebuild"):
		rebuild()


## A shock wave from `from` along `direction`.
func cast_shockwave(from: Vector3, direction: Vector3) -> Shockwave:
	var wave := Shockwave.new()
	wave.setup(structure, from, direction)
	add_child(wave)
	return wave


## Opens the orb in front of the player: it swallows the loose debris
## around for as long as it is held.
func start_orb() -> Orb:
	if orb == null or not is_instance_valid(orb) or not orb.open:
		orb = Orb.new()
		orb.setup(structure, player.camera)
		add_child(orb)
	return orb


## Lets go of the orb: it closes.
func drop_orb() -> void:
	if orb != null and is_instance_valid(orb):
		orb.close()
	orb = null


## Starts the level again, everything back up.
func rebuild() -> void:
	next_level = level
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


## Goes to the other level.
func switch_level() -> void:
	level = "house" if level == "course" else "course"
	rebuild()


## Something came off or broke up: dust, and bits thrown out.
func _on_released(at: Vector3, volume: float, velocity: Vector3) -> void:
	var size := pow(volume, 0.33)
	chips.disturb(at, 1.0 + size * 1.5)
	chips.burst(at, clampi(int(volume * 30.0), 2, 10), velocity * 0.6, 1.0 + size)
	if volume > 0.03:
		dust.puff(at, clampf(size * 2.2, 0.8, 3.5), velocity * 0.15)


func _build_world() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.ground_bottom_color = Color(0.42, 0.4, 0.38)
	sky.ground_horizon_color = Color(0.62, 0.62, 0.64)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	air = env

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	# Laid in world space: a square of the grid is always the same size.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = load(TEXTURES + "dark/texture_07.png")
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_world_triplanar = true
	floor_mat.uv1_scale = Vector3.ONE * 0.25
	floor_mat.metallic_specular = 0.2
	floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.material = floor_mat
	var ground := StaticBody3D.new()
	ground.collision_layer = Structure.LAYER_WORLD
	ground.collision_mask = 0
	var ground_shape := CollisionShape3D.new()
	ground_shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(ground_shape)
	var ground_look := MeshInstance3D.new()
	ground_look.mesh = plane
	ground.add_child(ground_look)
	add_child(ground)
