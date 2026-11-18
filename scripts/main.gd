class_name Main
extends Node3D
## The test bench, in greybox: a bare ground and one giant brute, yours,
## seen in third person. Nothing stands on it yet: what the brute breaks
## comes next, one material at a time (docs/CONCEPT.md).

## Where the brute starts.
const START := Vector3(0, 0.05, 0)
## The ground is this wide (m).
const GROUND := 400.0

var player: Player
var clock: PhysicsClock
var hud: Hud


func _ready() -> void:
	clock = PhysicsClock.new()
	add_child(clock)
	var options: Dictionary = get_node("/root/Launch").options
	_build_world()
	player = Player.new()
	add_child(player)
	player.global_position = START
	add_child(BlobShadow.new(player))
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
	print("BENCH ready")
	if options.has("mode"):
		var director := Director.new()
		director.options = options
		add_child(director)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rebuild"):
		rebuild()


## Puts the bench back as it was (starts the scene again).
func rebuild() -> void:
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func _build_world() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.2, 0.45, 0.9)
	sky.sky_horizon_color = Color(0.7, 0.85, 0.98)
	sky.ground_horizon_color = Color(0.7, 0.85, 0.98)
	sky.ground_bottom_color = Color(0.3, 0.34, 0.4)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky
	# (Lit by the sky alone, everything would turn blue.)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.95)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	# The sun casts no shadow: on the phone this was measured on, its
	# shadows were what cost the most (docs/PERFORMANCE.md). The brute has
	# a round one at its feet (BlobShadow).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.75
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = false
	add_child(sun)

	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND, GROUND)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground.gdshader")
	plane.material = mat
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var ground_shape := CollisionShape3D.new()
	ground_shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(ground_shape)
	var ground_look := MeshInstance3D.new()
	ground_look.mesh = plane
	ground_look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(ground_look)
	add_child(ground)
