class_name Course
extends Node3D
## A goal for the destruction: get to the light at the far end of a corridor.
## Dark rock does not break (the sides, a gate, a ledge); what is light does.
## Three things stand in the way, each asking for something else:
##   a wall right across                      -> break through it;
##   a gate plugged with blocks too heavy for
##   the shock wave to move                   -> the orb swallows them;
##   a ledge too high to jump onto, a tank
##   on legs at its foot                      -> bring the tank down and
##                                               climb its rubble;
## and the light itself is shut in a hut on the ledge.
## The corridor runs towards -Z from the start.

## You reached the light, in `seconds`, with `waves` shock waves.
signal finished(seconds: float, waves: int)

const TEXTURES := "res://addons/kenney_prototype_textures/"
const HALF := 4.0  ## half the width of the corridor (m)
const SIDES := 8.0  ## how high its sides are
const BACK := 9.0  ## the rock behind the start
const END := -46.0  ## and at the far end
const T := 0.35  ## thickness of what breaks
const WALL_Z := -2.0
const WALL_H := 5.0
const GATE_NEAR := -11.0
const GATE_FAR := -14.0
const GATE_HALF := 1.0  ## half the width of the way through
const GATE_H := 2.4
const GATE_TOP := 6.0
const LEDGE_Z := -24.0
## You jump 2.5 m: the ledge is out of reach from the ground, not from
## half a metre of rubble.
const LEDGE_H := 3.0
const TANK_HALF := 1.5
const TANK_DEEP := 2.8
const TANK_GAP := 0.4  ## between the tank and the ledge
## The tank weighs enough for two legs not to carry it: knock two out and
## it comes down.
const TANK_H := 2.6
const LEGS_H := 2.4
const LEG := 0.4
const BAY_HALF := 2.4  ## the bay of rock the tank stands in
const BAY_DEEP := 4.5
const HUT_Z := -37.0
const HUT_HALF := 2.0
const HUT_H := 2.8
const NEAR := 1.4  ## m from the light: you are there
const LIGHT := Color(1.0, 0.86, 0.35)

var start := Transform3D(Basis(), Vector3(0, 0.05, 6.0))  ## where you begin, looking down the corridor
var goal := Vector3(0, LEDGE_H, HUT_Z)  ## the foot of the light
var seconds := 0.0
var waves := 0
var running := false  ## the clock starts when you first move or fire
var done := false

var _player: Player
var _rock: StandardMaterial3D


## Adds the rock (to this node) and what breaks (to `s`, before its build()).
func build(s: Structure) -> void:
	# Rock: the checker of what breaks, but dark and bluish.
	_rock = StandardMaterial3D.new()
	_rock.albedo_texture = load(TEXTURES + "light/texture_07.png")
	_rock.albedo_color = Color(0.36, 0.39, 0.47)
	_rock.uv1_triplanar = true
	_rock.uv1_world_triplanar = true
	_rock.uv1_scale = Vector3.ONE * 0.25
	_rock.metallic_specular = 0.2
	_rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# The corridor.
	_block(Vector3(-HALF - 1.0, 0, END - 1.0), Vector3(-HALF, SIDES, BACK + 1.0))
	_block(Vector3(HALF, 0, END - 1.0), Vector3(HALF + 1.0, SIDES, BACK + 1.0))
	_block(Vector3(-HALF, 0, BACK), Vector3(HALF, SIDES, BACK + 1.0))
	_block(Vector3(-HALF, 0, END - 1.0), Vector3(HALF, SIDES, END))
	# 1. A wall right across.
	_box(s, Vector3(-HALF, 0, WALL_Z - T * 0.5), Vector3(HALF, WALL_H, WALL_Z + T * 0.5), House.WALL)
	# 2. A gate of rock, plugged. The plug does not touch the ground: nothing
	# holds it, so it comes loose at once, in blocks of several tonnes.
	_block(Vector3(-HALF, 0, GATE_FAR), Vector3(-GATE_HALF, GATE_TOP, GATE_NEAR))
	_block(Vector3(GATE_HALF, 0, GATE_FAR), Vector3(HALF, GATE_TOP, GATE_NEAR))
	_block(Vector3(-GATE_HALF, GATE_H, GATE_FAR), Vector3(GATE_HALF, GATE_TOP, GATE_NEAR))
	_box(
		s,
		Vector3(-GATE_HALF + 0.05, 0.06, GATE_FAR + 0.1),
		Vector3(GATE_HALF - 0.05, GATE_H - 0.1, GATE_NEAR - 0.1),
		House.SLAB
	)
	# 3. The ledge: the ground is LEDGE_H higher from here on. A tank stands
	# at its foot.
	var ledge := AABB(Vector3(-HALF, 0, END), Vector3(HALF * 2.0, LEDGE_H, LEDGE_Z - END))
	_block(ledge.position, ledge.end)
	s.footings.append(ledge)
	_tank(s)
	# 4. The hut the light is shut in, on the ledge.
	_hut(s)
	_light()


## Starts watching `player`: the clock, the shock waves, the arrival.
func watch(player: Player) -> void:
	_player = player
	player.fired.connect(
		func(_from: Vector3, _direction: Vector3) -> void:
			if not done:
				waves += 1
				running = true
	)


func _physics_process(delta: float) -> void:
	if done or _player == null:
		return
	var at := _player.global_position
	if not running and at.distance_to(start.origin) > 0.5:
		running = true
	if running:
		seconds += delta
	var off := at - goal
	if Vector2(off.x, off.z).length() < NEAR and absf(off.y) < 2.0:
		done = true
		finished.emit(seconds, waves)


## A block of rock from corner `lo` to corner `hi`.
func _block(lo: Vector3, hi: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Structure.LAYER_WORLD
	body.collision_mask = 0
	body.position = (lo + hi) * 0.5
	var box := BoxShape3D.new()
	box.size = hi - lo
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = hi - lo
	mesh.material = _rock
	var look := MeshInstance3D.new()
	look.mesh = mesh
	body.add_child(look)
	add_child(body)


## Something that breaks, from corner `lo` to corner `hi`.
func _box(s: Structure, lo: Vector3, hi: Vector3, tint: Color) -> void:
	s.add_box(Transform3D(Basis(), (lo + hi) * 0.5), hi - lo, tint)


## A solid tank on four legs, in a bay of rock at the foot of the ledge:
## the bay keeps the rubble where it is needed.
func _tank(s: Structure) -> void:
	var z0 := LEDGE_Z + TANK_GAP
	var z1 := z0 + TANK_DEEP
	_block(Vector3(-HALF, 0, LEDGE_Z), Vector3(-BAY_HALF, LEDGE_H, LEDGE_Z + BAY_DEEP))
	_block(Vector3(BAY_HALF, 0, LEDGE_Z), Vector3(HALF, LEDGE_H, LEDGE_Z + BAY_DEEP))
	for x: float in [-TANK_HALF, TANK_HALF - LEG]:
		for z: float in [z0, z1 - LEG]:
			_box(s, Vector3(x, 0, z), Vector3(x + LEG, LEGS_H, z + LEG), House.PILLAR)
	_box(s, Vector3(-TANK_HALF, LEGS_H, z0), Vector3(TANK_HALF, LEGS_H + TANK_H, z1), House.SLAB)


## Four walls and a roof on a pillar, with no way in.
func _hut(s: Structure) -> void:
	var w := HUT_HALF
	var y0 := LEDGE_H
	var y1 := LEDGE_H + HUT_H
	var z0 := HUT_Z - w
	var z1 := HUT_Z + w
	_box(s, Vector3(-w, y0, z0), Vector3(w, y1, z0 + T), House.WALL)
	_box(s, Vector3(-w, y0, z1 - T), Vector3(w, y1, z1), House.WALL)
	_box(s, Vector3(-w, y0, z0 + T), Vector3(-w + T, y1, z1 - T), House.WALL)
	_box(s, Vector3(w - T, y0, z0 + T), Vector3(w, y1, z1 - T), House.WALL)
	_box(s, Vector3(-w, y1, z0), Vector3(w, y1 + 0.3, z1), House.SLAB)
	_box(s, Vector3(-1.2, y0, z0 + T), Vector3(-0.75, y1, z0 + T + 0.45), House.PILLAR)


## The light to reach: a beam you see from the start, over the hut.
func _light() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(LIGHT.r, LIGHT.g, LIGHT.b, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := CylinderMesh.new()
	beam.top_radius = 0.22
	beam.bottom_radius = 0.22
	beam.height = 40.0
	beam.radial_segments = 12
	beam.material = mat
	var look := MeshInstance3D.new()
	look.mesh = beam
	look.position = goal + Vector3.UP * 20.0
	look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(look)
	var lamp := OmniLight3D.new()
	lamp.light_color = LIGHT
	lamp.light_energy = 1.5
	lamp.omni_range = 5.0
	lamp.position = goal + Vector3.UP * 1.2
	add_child(lamp)
