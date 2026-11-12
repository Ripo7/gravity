class_name Main
extends Node3D
## The test ground, in greybox: a house you can take apart with a shock
## wave (see Structure for how it breaks) and whose debris you can gather
## into an orb and throw back at it, walked around in first person.
## Textures: Kenney's prototype textures (CC0).

const TEXTURES := "res://addons/kenney_prototype_textures/"

var structure: Structure
var player: Player
var dust: Dust
var chips: Chips
var clock: PhysicsClock
var hud: Hud
var orb: Orb  ## the one being gathered, if any
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
	var t := Time.get_ticks_usec()
	House.build(structure, house_at)
	structure.build()
	build_ms = (Time.get_ticks_usec() - t) / 1000.0
	dust = Dust.new()
	add_child(dust)
	chips = Chips.new()
	add_child(chips)
	structure.released.connect(_on_released)
	player = Player.new()
	player.pieces = structure.pieces
	add_child(player)
	player.global_position = house_at * Vector3(0, 0.05, 15)
	player.fired.connect(cast_shockwave)
	player.gathering_changed.connect(
		func(on: bool) -> void:
			if on:
				start_orb()
			else:
				throw_orb()
	)
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = self
	ui.add_child(hud)
	hud.rebuild_pressed.connect(rebuild)
	if TouchControls.should_show():
		var touch := TouchControls.new()
		touch.player = player
		ui.add_child(touch)
	print(
		(
			"BUILD shards=%d bonds=%d vertices=%d in %.0f ms (tier %d)"
			% [
				structure.count,
				structure.bond_a.size(),
				structure.mesh.vertex_count,
				build_ms,
				Quality.tier()
			]
		)
	)
	var options: Dictionary = get_node("/root/Launch").options
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


## Starts gathering loose debris into an orb held in front of the player.
func start_orb() -> Orb:
	if orb == null or not is_instance_valid(orb) or orb.state != Orb.State.GATHER:
		orb = Orb.new()
		orb.setup(structure, player.camera)
		add_child(orb)
	return orb


## Throws the orb being gathered where the player looks.
func throw_orb() -> void:
	if orb != null and is_instance_valid(orb):
		orb.throw()
	orb = null


func _process(_delta: float) -> void:
	player.orb_fill = orb.fill() if orb != null and is_instance_valid(orb) else 0.0


## Puts the house back up (starts the scene again).
func rebuild() -> void:
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


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

	var sun := DirectionalLight3D.new()
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
