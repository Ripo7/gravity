class_name Fx
extends RefCounted
## Shared builders for particles and materials. CPU particles are used on
## purpose: identical on desktop and WebGL2 and cheap at these counts.

const LENS_SHADER := preload("res://shaders/lens.gdshader")

static var _spark_mesh: Mesh
static var _spark_material: StandardMaterial3D


static func spark_mesh() -> Mesh:
	if _spark_mesh == null:
		_spark_material = StandardMaterial3D.new()
		_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_material.albedo_color = Palette.VIOLET_HOT
		_spark_material.vertex_color_use_as_albedo = true
		_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, 0.06)
		quad.material = _spark_material
		_spark_mesh = quad
	return _spark_mesh


static func make_trail(radius: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = spark_mesh()
	p.amount = 24
	p.lifetime = 0.35
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.scale_amount_min = radius * 6.0
	p.scale_amount_max = radius * 12.0
	p.color = Palette.VIOLET
	p.color_ramp = _fade_ramp()
	return p


## Sparks spiralling into the core during the pull.
static func make_inflow(radius: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = spark_mesh()
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 0.0
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = radius
	p.gravity = Vector3.ZERO
	p.radial_accel_min = -radius * 9.0
	p.radial_accel_max = -radius * 7.0
	p.tangential_accel_min = radius * 2.0
	p.tangential_accel_max = radius * 4.0
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Palette.VIOLET_HOT
	p.color_ramp = _fade_ramp()
	return p


## One-shot burst of sparks flying outward.
static func make_outflow(speed: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = spark_mesh()
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -6, 0)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed * 1.1
	p.damping_min = speed * 0.6
	p.damping_max = speed * 1.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	p.color = Palette.VIOLET_HOT
	p.color_ramp = _fade_ramp()
	return p


static func lens_material(strength: float, core: float, rim: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LENS_SHADER
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("violet", Palette.VIOLET)
	m.set_shader_parameter("deep", Palette.VIOLET_DEEP)
	return m


static func sphere(radius: float, material: Material, segments := 32) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = int(segments / 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	return g
