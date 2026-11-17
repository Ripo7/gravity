class_name Dust
extends Node3D
## Puffs of dust where something breaks: a few clouds that swell, drift up
## a little and thin out, in the colour of what broke. Each is a real cloud
## rendered in Blender (tools/blender/dust.py: a volume lit from above,
## sixteen frames of its life on one sheet), played once through. A small
## pool of emitters used in turn, and never more than a few puffs a frame.

const POOL := 12
const PER_FRAME := 3
const SHEET := "res://assets/fx/dust.png"
## Frames across the sheet, and down.
const ACROSS := 4

var _emitters: Array[CPUParticles3D] = []
var _next := 0
var _this_frame := 0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = ACROSS
	mat.particles_anim_v_frames = ACROSS
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(SHEET)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.material = mat
	var swell := Curve.new()
	swell.add_point(Vector2(0, 0.35))
	swell.add_point(Vector2(1, 1.0))
	# (The sheet thins the cloud out by itself; this only makes sure the
	# last of it is gone.)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.7, Color(1, 1, 1, 1))
	for k in POOL:
		var p := CPUParticles3D.new()
		p.mesh = quad
		p.amount = int(Quality.pick(5, 7, 9))
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.9
		p.lifetime = 1.6
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.3
		p.direction = Vector3.UP
		p.spread = 180.0
		p.gravity = Vector3(0, 0.4, 0)
		p.initial_velocity_min = 0.3
		p.initial_velocity_max = 1.4
		p.damping_min = 1.0
		p.damping_max = 2.0
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.3
		p.scale_amount_curve = swell
		p.anim_speed_min = 1.0
		p.anim_speed_max = 1.0
		p.anim_offset_max = 0.06
		p.angle_max = 360.0
		p.color_ramp = fade
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_emitters.append(p)


func _process(_delta: float) -> void:
	_this_frame = 0


## A puff at `at`, about `size` metres across, drifting with `drift`, of
## dust in `colour`.
func puff(at: Vector3, size: float, drift := Vector3.ZERO, colour := Color(0.78, 0.77, 0.74)) -> void:
	if _this_frame >= PER_FRAME:
		return
	_this_frame += 1
	var p := _emitters[_next]
	_next = (_next + 1) % POOL
	p.global_position = at
	p.color = Color(colour, 0.75)
	p.emission_sphere_radius = size * 0.3
	p.scale = Vector3.ONE * size
	p.direction = (drift + Vector3.UP * 0.5).normalized()
	p.spread = 70.0
	p.initial_velocity_max = 1.4 + drift.length() * 0.25
	p.restart()
