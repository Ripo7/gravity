class_name Main
extends Node3D
## The ground the game is played on, in greybox, and two brutes to take it
## apart, one of them yours, seen in third person. Two grounds: a toy city
## in which the brutes are giants (City: the game), and a house their own
## size (House: where the destruction is tested). See Structure for how
## things break.
## Textures: Kenney's prototype textures (CC0).

const TEXTURES := "res://addons/kenney_prototype_textures/"

var structure: Structure
var player: Player
var dust: Dust
var chips: Chips
var clock: PhysicsClock
var hud: Hud
## Which ground: "city" or "house" (set before it enters the tree, or with
## the launch option --level=).
var level := "city"
## Where the house stands.
var house_at := Transform3D(Basis(), Vector3(0, 0, -4))
## The level's own space: the house's, or the world's for the city.
var level_at := Transform3D.IDENTITY
## The other brute, and where it starts (in the house's space): near where
## you start, off to the right. `fight`: it attacks (off for tests and
## scripted runs: it only stands there).
var brute: Brute
var brute_at := Vector3(4.0, 0.05, 11.5)
var fight := true
## Milliseconds it took to cut and bond what stands.
var build_ms := 0.0


func _ready() -> void:
	clock = PhysicsClock.new()
	add_child(clock)
	_build_world()
	var options: Dictionary = get_node("/root/Launch").options
	level = options.get("level", level)
	structure = Structure.new()
	structure.most_crumbs = int(Quality.pick(250, 450, 800))
	add_child(structure)
	var t := Time.get_ticks_usec()
	var starts := house_at * Vector3(0, 0.05, 15)
	var brute_starts := house_at * brute_at
	if level == "house":
		level_at = house_at
		House.build(structure, house_at)
	else:
		structure.mesh.squares_per_metre = City.SQUARES_PER_METRE
		structure.density = City.DENSITY
		City.build(structure, Transform3D.IDENTITY)
		_pave()
		starts = City.PLAYER
		brute_starts = City.BRUTE
	structure.build()
	build_ms = (Time.get_ticks_usec() - t) / 1000.0
	dust = Dust.new()
	add_child(dust)
	chips = Chips.new()
	add_child(chips)
	structure.released.connect(_on_released)
	player = Player.new()
	add_child(player)
	player.global_position = starts
	player.fighter.structure = structure
	brute = Brute.new()
	brute.watches = player
	brute.ai = fight
	brute.position = brute_starts
	brute.fighter.structure = structure
	add_child(brute)
	if fight:
		player.lock()  # the fight starts locked on; a button lets go
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
	if options.has("mode"):
		var director := Director.new()
		director.options = options
		add_child(director)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rebuild"):
		rebuild()


## What a brute's fist does where the line from `from` along `direction`
## first meets something that stands: scripted runs and tests take the
## level apart with it, without a fight. Returns how many shards went.
func blow(from: Vector3, direction: Vector3) -> int:
	var along := direction.normalized()
	var ray := PhysicsRayQueryParameters3D.create(
		from, from + along * 80.0, Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return 0
	return Fighter.smash(structure, hit["position"], Fighter.HOLE[2], along * 6.0)


## A tour of the level for the showcase: where to stand and what to look
## at, stop after stop.
func tour() -> Array[Array]:
	var stops: Array[Array] = []
	for stop in House.tour() if level == "house" else City.tour():
		stops.append([level_at * (stop[0] as Vector3), level_at * (stop[1] as Vector3)])
	return stops


## Puts the level back up (starts the scene again).
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


## The pavements of the city: a light pad under each block and under the
## square, a finger above the road (only to look at).
func _pave() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEXTURES + "light/texture_07.png")
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.5
	for pad: Array in City.pads():
		var size: Vector2 = pad[1]
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x, 0.03, size.y)
		slab.material = mat
		var look := MeshInstance3D.new()
		look.mesh = slab
		look.position = (pad[0] as Vector3) + Vector3(0, 0.015, 0)
		look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(look)


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
