class_name Main
extends Node3D
## The ground the game is played on, in greybox, and two brutes to take it
## apart, one of them yours, seen in third person. Two grounds: a toy city
## in which the brutes are giants (City: the game), and a house their own
## size (House: where the destruction is tested). See Structure for how
## things break.
## Textures: Kenney's prototype textures (CC0).

const TEXTURES := "res://addons/kenney_prototype_textures/"
## The pace below which the picture gives something up (frames a second),
## and over how long it is told (s). See keep_pace.
const SLOW := 40.0
const PACE_OVER := 3.0

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
## The city, if that is the ground, and the number it is made up from: a
## new one each time unless it is set before the scene enters the tree, or
## told with the launch option --city= (or --seed=, for a scripted run).
var city: City
var city_number := -1
## The level's own space: the house's, or the world's for the city.
var level_at := Transform3D.IDENTITY
## The other brute, and where it starts (in the house's space): near where
## you start, off to the right. `fight`: it attacks (off for tests and
## scripted runs: it only stands there).
var brute: Brute
var brute_at := Vector3(4.0, 0.05, 11.5)
var fight := true
## How many things the picture has given up to keep pace (see keep_pace):
## 0, 1 (the sun's shadows) or 2 (a quarter of the resolution as well).
var eased := 0
## Milliseconds it took to cut and bond what stands.
var build_ms := 0.0

var _sun: DirectionalLight3D
var _floor: PlaneMesh
var _blobs: Array[MeshInstance3D] = []
var _pacing := false
var _paced := 0.0
var _frames := 0
var _slow := 0
var _settled := false


func _ready() -> void:
	clock = PhysicsClock.new()
	add_child(clock)
	var options: Dictionary = get_node("/root/Launch").options
	level = options.get("level", level)
	_build_world()
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
		if city_number < 0:
			city_number = int(options.get("city", options.get("seed", randi() % 100000)))
		city = City.new(city_number)
		structure.density = City.DENSITY
		city.build(structure, Transform3D.IDENTITY)
		_pave()
		starts = city.player_start
		brute_starts = city.brute_start
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
	for body: Node3D in [player, brute]:
		_blobs.append(_blob(body))
	# (A scripted run is drawn the same way from end to end.)
	_pacing = not options.has("mode") and DisplayServer.get_name() != "headless"
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
	if city != null:
		print(
			(
				"CITY number=%d blocks=%d towers=%d offices=%d houses=%d cars=%d railway=%d"
				% [
					city.number,
					city.blocks.size(),
					city.towers.size(),
					city.offices.size(),
					city.houses.size(),
					city.cars.size(),
					city.railway.size() / 2
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


func _process(delta: float) -> void:
	if _pacing:
		keep_pace(delta)


## Told each frame how long the last one took. When the picture is drawn at
## fewer than SLOW frames a second over PACE_OVER s, twice running, it gives
## something up for good: first the sun's shadows (the brutes keep a round
## one at their feet), then a quarter of the resolution. The first stretch
## after the start does not count, nor one in which the page was away.
func keep_pace(delta: float) -> void:
	if delta > 0.25:
		_paced = 0.0
		_frames = 0
		return
	_paced += delta
	_frames += 1
	if _paced < PACE_OVER:
		return
	var rate := _frames / _paced
	_paced = 0.0
	_frames = 0
	if not _settled:
		_settled = true
		return
	_slow = _slow + 1 if rate < SLOW else 0
	if _slow < 2 or eased >= 2:
		return
	_slow = 0
	eased += 1
	if eased == 1:
		_sun.shadow_enabled = false
		for blob in _blobs:
			blob.visible = true
	else:
		get_viewport().scaling_3d_scale = 0.75
	print("EASED %d at %.0f frames a second" % [eased, rate])


## A round shadow at the feet of `body`, for when the sun casts none.
func _blob(body: Node3D) -> MeshInstance3D:
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0)])
	var round := GradientTexture2D.new()
	round.gradient = fade
	round.fill = GradientTexture2D.FILL_RADIAL
	round.fill_from = Vector2(0.5, 0.5)
	round.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = round
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flat := PlaneMesh.new()
	flat.size = Vector2(1.7, 1.7)
	flat.material = mat
	var blob := MeshInstance3D.new()
	blob.mesh = flat
	blob.position.y = 0.04
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.visible = false
	body.add_child(blob)
	return blob


## A tour of the level for the showcase: where to stand and what to look
## at, stop after stop.
func tour() -> Array[Array]:
	var stops: Array[Array] = []
	for stop in House.tour() if city == null else city.tour():
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


## The ground of the city: its road, and a slab under each block and under
## the square, a finger above the road (only to look at). What is drawn on
## them is told by shaders/ground.gdshader, from where the blocks are.
func _pave() -> void:
	var mat := _ground()
	_floor.material = mat
	for pad: Array in city.pads():
		var size: Vector2 = pad[1]
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x, 0.03, size.y)
		slab.material = mat
		var look := MeshInstance3D.new()
		look.mesh = slab
		look.position = (pad[0] as Vector3) + Vector3(0, 0.015, 0)
		look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(look)


## What the ground of the city is drawn with: told where its blocks and
## its streets are, what each block is, and where things stand on it.
func _ground() -> ShaderMaterial:
	var area := city.bounds()
	# (Those there are none of are put far away.)
	var blocks := PackedVector4Array()
	var streets := PackedVector4Array()
	var districts := PackedVector4Array()
	blocks.resize(4)
	blocks.fill(Vector4(1e4, 0, 1e4, 0))
	streets.resize(3)
	streets.fill(Vector4(1e4, 0, 1e4, 0))
	districts.resize(4)
	for way in 2:
		var beside := city.columns if way == 0 else city.rows
		var between := city.avenues(way)
		for k in beside.size():
			blocks[k][way * 2] = beside[k].x
			blocks[k][way * 2 + 1] = beside[k].y
		for k in between.size():
			streets[k][way * 2] = between[k].x
			streets[k][way * 2 + 1] = between[k].y
	for k in city.kinds.size():
		districts[k / city.columns.size()][k % city.columns.size()] = city.kinds[k]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground.gdshader")
	mat.set_shader_parameter("shade", city.ground_shade())
	mat.set_shader_parameter("area", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
	mat.set_shader_parameter("blocks", blocks)
	mat.set_shader_parameter("streets", streets)
	mat.set_shader_parameter("districts", districts)
	mat.set_shader_parameter("ring", minf(city.square.size.x, city.square.size.y) * 0.5 - 1.0)
	return mat


func _build_world() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.ground_bottom_color = Color(0.42, 0.4, 0.38)
	sky.ground_horizon_color = Color(0.62, 0.62, 0.64)
	if level != "house":
		# Over the city: a blue sky, and a road with no squares on it.
		sky.sky_top_color = Color(0.2, 0.45, 0.9)
		sky.sky_horizon_color = Color(0.7, 0.85, 0.98)
		sky.ground_horizon_color = Color(0.7, 0.85, 0.98)
		sky.ground_bottom_color = Color(0.3, 0.34, 0.4)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	if level != "house":
		# (Lit by the sky alone, everything would turn blue.)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.86, 0.88, 0.95)
		env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.75
	if level != "house":
		sun.light_color = Color(1.0, 0.95, 0.86)
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
	if level != "house":
		floor_mat.albedo_texture = null
		floor_mat.albedo_color = Color(0.25, 0.24, 0.25)
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.material = floor_mat
	_floor = plane
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
