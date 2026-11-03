class_name DustSystem
extends Node3D
## Pooled dust clouds and flying chips for breaks and impacts.
## CPU particles behave the same on desktop and WebGL; a fixed pool and a
## per-second budget keep big collapses from flooding the screen.

const POOL := 20
const CHIP_POOL := 16
const MAX_PER_SECOND := 30

const DUST_COLORS := {
	Materials.Kind.CONCRETE: Color(0.82, 0.8, 0.76, 0.55),
	Materials.Kind.WOOD: Color(0.8, 0.68, 0.52, 0.45),
	Materials.Kind.METAL: Color(0.7, 0.72, 0.76, 0.35),
}
const CHIP_COLORS := {
	Materials.Kind.CONCRETE: Color(0.7, 0.68, 0.64),
	Materials.Kind.WOOD: Color(0.72, 0.52, 0.32),
	Materials.Kind.METAL: Color(0.62, 0.66, 0.72),
}

var _dust: Array[CPUParticles3D] = []
var _chips: Array[CPUParticles3D] = []
var _next_dust := 0
var _next_chip := 0
var _spent := 0.0  # budget used, drains every second


func _ready() -> void:
	var dust_mesh := _dust_mesh()
	var chip_mesh := _chip_mesh()
	for i in POOL:
		var p := CPUParticles3D.new()
		p.mesh = dust_mesh
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.85
		p.lifetime = 2.2
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.direction = Vector3.UP
		p.spread = 70.0
		p.gravity = Vector3(0, 0.25, 0)
		p.damping_min = 2.0
		p.damping_max = 3.5
		p.angular_velocity_min = -40.0
		p.angular_velocity_max = 40.0
		p.scale_amount_curve = _grow_curve()
		p.color_ramp = _fade_ramp()
		_dust.append(p)
		add_child(p)
	for i in CHIP_POOL:
		var c := CPUParticles3D.new()
		c.mesh = chip_mesh
		c.one_shot = true
		c.emitting = false
		c.explosiveness = 1.0
		c.lifetime = 0.9
		c.local_coords = false
		c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		c.direction = Vector3.UP
		c.spread = 160.0
		c.gravity = Vector3(0, -18, 0)
		c.angular_velocity_min = -720.0
		c.angular_velocity_max = 720.0
		c.particle_flag_rotate_y = true
		c.scale_amount_min = 0.5
		c.scale_amount_max = 1.4
		_chips.append(c)
		add_child(c)


func _process(delta: float) -> void:
	_spent = maxf(_spent - MAX_PER_SECOND * delta, 0.0)


## A dust cloud of roughly `radius` metres.
func puff(at: Vector3, radius: float, kind: int, amount := 10) -> void:
	if _spent > MAX_PER_SECOND:
		return
	_spent += 1.0
	var p := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % POOL
	p.global_position = at
	p.amount = clampi(amount, 4, 40)
	p.emission_sphere_radius = maxf(radius * 0.5, 0.1)
	p.initial_velocity_min = 0.3 + radius * 0.4
	p.initial_velocity_max = 0.8 + radius * 1.2
	p.scale_amount_min = 0.6 + radius * 0.5
	p.scale_amount_max = 1.2 + radius * 1.1
	p.lifetime = 1.6 + minf(radius, 3.0) * 0.5
	p.color = DUST_COLORS.get(kind, DUST_COLORS[Materials.Kind.CONCRETE])
	p.restart()


## Small flying fragments that are not simulated as bodies.
func chips(at: Vector3, radius: float, kind: int, speed := 5.0, amount := 12) -> void:
	if _spent > MAX_PER_SECOND:
		return
	_spent += 0.5
	var c := _chips[_next_chip]
	_next_chip = (_next_chip + 1) % CHIP_POOL
	c.global_position = at
	c.amount = clampi(amount, 4, 32)
	c.emission_sphere_radius = maxf(radius * 0.4, 0.05)
	c.initial_velocity_min = speed * 0.4
	c.initial_velocity_max = speed
	c.color = CHIP_COLORS.get(kind, CHIP_COLORS[Materials.Kind.CONCRETE])
	c.restart()


func _dust_mesh() -> Mesh:
	var tex := GradientTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	tex.gradient = g
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat
	return quad


func _chip_mesh() -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.05, 0.06)
	box.material = mat
	return box


static func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.35))
	c.add_point(Vector2(0.3, 0.85))
	c.add_point(Vector2(1, 1.0))
	return c


static func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.08, Color(1, 1, 1, 1.0))
	g.add_point(0.5, Color(1, 1, 1, 0.6))
	return g
