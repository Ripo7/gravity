class_name BlastFx
extends Node3D
## Visuals for one GravityBlast: a lensing black-hole core during the pull,
## then a lensing shockwave, sparks and a violet flash on the burst.

const SHOCK_TIME := 0.5

var params: BlastParams
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _shock: MeshInstance3D
var _inflow: CPUParticles3D
var _light: OmniLight3D
var _t := 0.0
var _burst_t := -1.0


func setup(p: BlastParams, at: Vector3, blast: GravityBlast) -> void:
	params = p
	position = at
	blast.burst.connect(_on_burst)


func _ready() -> void:
	_core = Fx.sphere(1.0, Fx.lens_material(0.02, 1.0, 1.4))
	_halo = Fx.sphere(1.0, Fx.lens_material(0.05 + params.charge * 0.07, 0.0, 0.25))
	_core.scale = Vector3.ONE * 0.01
	_halo.scale = Vector3.ONE * 0.01
	add_child(_halo)
	add_child(_core)
	_inflow = Fx.make_inflow(params.radius * 0.55, int(40 + params.charge * 120))
	add_child(_inflow)
	_light = OmniLight3D.new()
	_light.light_color = Palette.VIOLET
	_light.omni_range = params.radius
	_light.light_energy = 0.0
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	if _burst_t < 0.0:
		# Pull: the core swells and the lens halo grows around it.
		var k := clampf(_t / params.pull_time, 0.0, 1.0)
		var e := ease(k, 0.4)
		var core_r := params.core_radius * (0.35 + 0.65 * e)
		# Small dark core so the pieces gathering around it stay visible.
		_core.scale = Vector3.ONE * core_r * 0.55
		_halo.scale = Vector3.ONE * core_r * (2.4 + sin(_t * 30.0) * 0.08)
		_light.light_energy = 1.0 + e * 3.0
		return
	var b := _t - _burst_t
	var k := clampf(b / SHOCK_TIME, 0.0, 1.0)
	# Core collapses almost instantly.
	_core.scale = Vector3.ONE * maxf(params.core_radius * (1.0 - b * 10.0), 0.001)
	_core.visible = b < 0.1
	_halo.visible = b < 0.1
	# Shockwave: expands fast then slows, lens and rim fade out.
	var r := lerpf(params.core_radius, params.radius * 1.05, ease(k, 0.25))
	_shock.scale = Vector3.ONE * r
	var m := _shock.material_override as ShaderMaterial
	m.set_shader_parameter("alpha_scale", 1.0 - k)
	m.set_shader_parameter("rim", (1.0 - k) * 1.2)
	_light.light_energy = (1.0 + 2.5 * params.charge) * (1.0 - k) * (1.0 - k)
	if b > 1.2:
		queue_free()


func _on_burst() -> void:
	_burst_t = _t
	_inflow.emitting = false
	_shock = Fx.sphere(1.0, Fx.lens_material(0.04 + params.charge * 0.05, 0.0, 1.2), 40)
	_shock.scale = Vector3.ONE * params.core_radius
	add_child(_shock)
	var sparks := Fx.make_outflow(params.burst_speed * 1.2, int(60 + params.charge * 180))
	add_child(sparks)
	sparks.emitting = true
