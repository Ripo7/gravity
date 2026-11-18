class_name Main
extends Node3D
## The test bench, in greybox: a bare ground, one giant brute, yours, seen
## in third person, and a few pieces of one matter for it to break. What
## breaks is worked out here one matter at a time (docs/CONCEPT.md):
## concrete so far.

## Where the brute starts.
const START := Vector3(0, 0.05, 0)
## The ground is this wide (m).
const GROUND := 400.0
## What stands on the bench, in concrete. A column on its own; a wall of
## WALL_PANELS panels side by side; a slab on four columns, SPAN m apart.
const COLUMN := Vector3(0.4, 2.6, 0.4)
const COLUMN_AT := Vector3(-3.5, 0, -6)
const PANEL := Vector3(1.2, 2.4, 0.35)
const WALL_AT := Vector3(0, 0, -8)
const WALL_PANELS := 3
const POST := Vector3(0.4, 2.2, 0.4)
const SLAB := Vector3(3.6, 0.3, 3.6)
const SLAB_AT := Vector3(5, 0, -7.5)
const SPAN := 3.2

var player: Player
var structure: Structure
var clock: PhysicsClock
var hud: Hud
## The share of real gravity that pulls what has come off (see Rubble):
## set on the screen, kept when the bench is put back.
var fall := Rubble.FALL:
	set = set_fall
## On the bench: the column that stands alone, the panels of the wall, the
## four columns under the slab, the slab (the numbers of their pieces).
var column := -1
var panels := PackedInt32Array()
var posts := PackedInt32Array()
var slab := -1


func _ready() -> void:
	clock = PhysicsClock.new()
	add_child(clock)
	var options: Dictionary = get_node("/root/Launch").options
	_build_world()
	_lay_bench()
	player = Player.new()
	add_child(player)
	player.global_position = START
	player.blow.connect(_on_blow)
	add_child(BlobShadow.new(player))
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = self
	ui.add_child(hud)
	hud.rebuild_pressed.connect(rebuild)
	hud.fall_set.connect(set_fall)
	if TouchControls.should_show():
		var touch := TouchControls.new()
		touch.player = player
		ui.add_child(touch)
	print("BENCH ready: %d pieces, %d blocks" % [structure.pieces, structure.count])
	if options.has("mode"):
		var director := Director.new()
		director.options = options
		add_child(director)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rebuild"):
		rebuild()


func set_fall(share: float) -> void:
	fall = clampf(share, Rubble.FALL_LEAST, Rubble.FALL_MOST)
	if structure != null:
		structure.rubble.fall = fall


## Puts the bench back as it was, and the brute where it started.
func rebuild() -> void:
	structure.free()
	_lay_bench()
	player.global_position = START
	player.velocity = Vector3.ZERO


func _on_blow(from: Vector3, to: Vector3, power: int) -> void:
	structure.strike(from, to, power)


## What stands on the bench, in concrete: a column, a wall, a slab on four
## columns.
func _lay_bench() -> void:
	structure = Structure.new()
	add_child(structure)
	structure.rubble.fall = fall
	column = _stand(COLUMN, COLUMN_AT)
	panels.clear()
	for k in WALL_PANELS:
		var along := (k - (WALL_PANELS - 1) * 0.5) * PANEL.x
		panels.append(_stand(PANEL, WALL_AT + Vector3(along, 0, 0)))
	posts.clear()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		posts.append(_stand(POST, SLAB_AT + Vector3(corner.x, 0, corner.y) * SPAN * 0.5))
	slab = _stand(SLAB, SLAB_AT + Vector3.UP * POST.y)
	structure.build()


## A piece of concrete `size` across, its foot at `foot`. Returns its
## number.
func _stand(size: Vector3, foot: Vector3) -> int:
	var middle := Transform3D(Basis(), foot + Vector3.UP * size.y * 0.5)
	return structure.add_piece(Matter.CONCRETE, middle, size)


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
