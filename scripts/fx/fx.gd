class_name Fx
extends RefCounted
## Small effects built in code.


## Streaks of air shot out in a cone along -Z (a shock wave), all at once.
static func make_streaks(amount: int, spread: float) -> CPUParticles3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var line := BoxMesh.new()
	line.size = Vector3(0.06, 1.8, 0.06)
	line.material = m
	var p := CPUParticles3D.new()
	p.mesh = line
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 0, -1)
	p.spread = spread
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 28.0
	p.initial_velocity_max = 46.0
	p.damping_min = 40.0
	p.damping_max = 60.0
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.color = Color(1, 1, 1, 0.75)
	p.color_ramp = fade_ramp()
	return p


## Streaks of air drawn in from `reach` metres all round to the middle (an
## orb gathering), for as long as it is emitting.
static func make_inflow(amount: int, reach: float) -> CPUParticles3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var line := BoxMesh.new()
	line.size = Vector3(0.02, 0.7, 0.02)
	line.material = m
	var p := CPUParticles3D.new()
	p.mesh = line
	p.amount = amount
	p.lifetime = 0.45
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = reach
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	# Falling towards the middle: there in one lifetime.
	p.radial_accel_min = -2.0 * reach / (p.lifetime * p.lifetime)
	p.radial_accel_max = p.radial_accel_min
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color = Color(0.8, 0.9, 1.0, 0.45)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.4, Color(1, 1, 1, 1))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Opaque, then fading out over the last two thirds of a particle's life.
static func fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 1))
	return g
