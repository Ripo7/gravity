class_name Main
extends Node3D
## Starting point for a new concept: a lit floor, a camera, and crates that
## fall where you tap or click. It checks that physics, input (mouse and
## touch) and the web build work before the real idea goes in.

## Crates kept at once (the oldest goes first).
const MAX_CRATES := 60
const CRATE := 0.8

var camera: Camera3D
var crates: Array[RigidBody3D] = []
var _mesh: BoxMesh
var _shape: BoxShape3D


func _ready() -> void:
	_build_world()
	for i in 6:
		drop_crate(Vector3(randf_range(-1.5, 1.5), 3.0 + i * 1.2, randf_range(-1.5, 1.5)))


func _unhandled_input(event: InputEvent) -> void:
	# A tap arrives as a mouse click too (touch is emulated as mouse).
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		drop_at_screen(click.position)


## Drops a crate above the spot of the floor under `screen_pos`.
func drop_at_screen(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit != null:
		drop_crate((hit as Vector3) + Vector3.UP * 6.0)


## A crate at `at`, tumbling a little.
func drop_crate(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = _shape
	body.add_child(shape)
	var look := MeshInstance3D.new()
	look.mesh = _mesh
	body.add_child(look)
	add_child(body)
	body.global_position = at
	body.rotation = Vector3(randf(), randf(), randf()) * TAU
	crates.append(body)
	if crates.size() > MAX_CRATES:
		crates.pop_front().queue_free()
	return body


func _build_world() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.ground_bottom_color = Color(0.42, 0.4, 0.38)
	sky.ground_horizon_color = Color(0.62, 0.62, 0.64)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.5, 0.48, 0.45)
	floor_mat.metallic_specular = 0.05
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.material = floor_mat
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	ground_shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(ground_shape)
	var ground_look := MeshInstance3D.new()
	ground_look.mesh = plane
	ground.add_child(ground_look)
	add_child(ground)

	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.55, 0.36, 0.96)
	_mesh = BoxMesh.new()
	_mesh.size = Vector3.ONE * CRATE
	_mesh.material = crate_mat
	_shape = BoxShape3D.new()
	_shape.size = Vector3.ONE * CRATE

	camera = Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 5, 9), Vector3(0, 0.5, 0))

	var hint := Label.new()
	hint.text = "Nouveau concept : touche ou clique pour lâcher une caisse"
	hint.position = Vector2(24, 20)
	hint.add_theme_font_size_override("font_size", 28)
	hint.add_theme_color_override("font_color", Color(0.12, 0.1, 0.2))
	var ui := CanvasLayer.new()
	ui.add_child(hint)
	add_child(ui)
