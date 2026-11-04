class_name GravityOrb
extends Node3D
## Singularity power: an orb of gravitational wave appears at the aimed spot,
## swells while its fuse burns, then goes off as a GravityBlast.

const ORB_MATERIAL := preload("res://materials/power.tres")

var tier := 0
var params: BlastParams
var fuse := 1.0
var _t := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _world: GameWorld


func setup(world: GameWorld, at: Vector3, size_tier: int) -> void:
	_world = world
	tier = size_tier
	params = PowerDefs.gravity_params(tier)
	fuse = PowerDefs.GRAVITY_FUSE[tier]
	position = at


func _ready() -> void:
	_core = Fx.sphere(1.0, ORB_MATERIAL, 24)
	add_child(_core)
	_halo = Fx.sphere(1.0, Fx.lens_material(0.05 + params.charge * 0.05, 0.4, 0.8), 24)
	add_child(_halo)
	_ring = _make_ring()
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = Palette.VIOLET
	_light.omni_range = params.radius * 0.6
	add_child(_light)
	add_child(Fx.make_inflow(params.core_radius * 2.5, int(20 + params.charge * 60)))
	Sfx.play("orb", global_position, -8.0 + tier * 3.0, 1.15 - tier * 0.15)
	_update(0.0)


func _process(delta: float) -> void:
	_t += delta
	_update(delta)
	if _t >= fuse:
		if _world:
			_world.detonate(global_position, params)
		queue_free()


func _update(_delta: float) -> void:
	var k := clampf(_t / fuse, 0.0, 1.0)
	# Pops in, then swells and trembles faster as the fuse runs out.
	var pop := ease(clampf(_t / 0.18, 0.0, 1.0), 0.4)
	var r := params.ball_radius * (1.2 + 1.6 * k) * pop
	var shake := sin(_t * (18.0 + k * 50.0)) * 0.06 * k
	_core.scale = Vector3.ONE * r * (1.0 + shake)
	_halo.scale = Vector3.ONE * r * (2.2 + k * 0.8)
	_light.light_energy = 1.0 + k * 3.0
	# Ground ring shrinks toward the orb: a countdown you can read anywhere.
	_ring.scale = Vector3.ONE * lerpf(params.radius, params.core_radius, ease(k, 0.6))
	var m := _ring.material_override as StandardMaterial3D
	m.albedo_color.a = 0.25 + 0.5 * k


func _make_ring() -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Palette.VIOLET, 0.4)
	m.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
