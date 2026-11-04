class_name Vortex
extends Node3D
## Black hole power. It opens where you aim and does not explode: everything
## inside its radius is torn loose and spins around the core like a storm.
## Just outside the radius is a band that is not pulled but shredded:
## blocks there crack and break, and it hurts you. When it closes, the
## spinning pieces fly off along their orbit.

signal closed

const PORTAL_SHADER := preload("res://shaders/portal.gdshader")
const FADE := 0.6
const TICK := 0.1  ## seconds between damage passes

var center := Vector3.ZERO
var caught := 0  ## pieces currently orbiting
var _world: GameWorld
var _t := 0.0
var _tick := 0.0
var _core: MeshInstance3D
var _shell: MeshInstance3D
var _disc: MeshInstance3D
var _ring_inner: MeshInstance3D
var _ring_outer: MeshInstance3D
var _light: OmniLight3D
var _inflow: CPUParticles3D
var _pull_started := false


func setup(world: GameWorld, at: Vector3) -> void:
	_world = world
	center = at
	position = at


func _ready() -> void:
	add_to_group("vortex")
	var r := PowerDefs.VORTEX_RADIUS
	_core = Fx.sphere(1.0, Fx.lens_material(0.04, 1.0, 1.6), 32)
	add_child(_core)
	_shell = Fx.sphere(1.0, Fx.lens_material(0.025, 0.0, 0.35), 40)
	add_child(_shell)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	disc.radial_segments = 64
	_disc = MeshInstance3D.new()
	_disc.mesh = disc
	var m := ShaderMaterial.new()
	m.shader = PORTAL_SHADER
	m.set_shader_parameter("violet", Palette.VIOLET)
	_disc.material_override = m
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	_ring_inner = _ring(Color(Palette.VIOLET, 0.55))
	_ring_outer = _ring(Color(0.95, 0.15, 0.35, 0.5))
	_light = OmniLight3D.new()
	_light.light_color = Palette.VIOLET
	_light.omni_range = r * 1.2
	add_child(_light)
	_inflow = Fx.make_inflow(r * 0.7, 160)
	add_child(_inflow)
	Sfx.play("orb", center, 2.0, 0.85)
	_update_visuals()


func _ring(col: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 96
	torus.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func is_pulling() -> bool:
	return _t >= PowerDefs.VORTEX_SPINUP and _t < PowerDefs.VORTEX_SPINUP + PowerDefs.VORTEX_DURATION


func _physics_process(delta: float) -> void:
	_t += delta
	_update_visuals()
	if _t >= PowerDefs.VORTEX_SPINUP + PowerDefs.VORTEX_DURATION + FADE:
		closed.emit()
		queue_free()
		return
	if not is_pulling() or _world == null:
		return
	if not _pull_started:
		_pull_started = true
		Sfx.play("implode", center, 4.0, 0.7)
	_spin_debris(delta)
	_spin_stones(delta)
	_tick += delta
	if _tick >= TICK:
		var r := PowerDefs.VORTEX_RADIUS
		var outer := r + PowerDefs.VORTEX_BAND
		_world.structures.apply_field(
			center, r, outer, PowerDefs.VORTEX_DPS_INSIDE, PowerDefs.VORTEX_DPS_BAND, _tick
		)
		_world.structures.tear_clusters(center, r)
		_shred_band(_tick)
		_hurt_player(_tick)
		_tick = 0.0


## Desired orbit velocity at `p`: around the vertical axis, faster near the
## core, drawn toward a thick disc at the core's height.
func _orbit_velocity(p: Vector3, layer: float) -> Vector3:
	var off := p - center
	var flat := Vector3(off.x, 0, off.z)
	var r := flat.length()
	if r < 0.05:
		flat = Vector3.RIGHT * 0.05
		r = 0.05
	var out := flat / r
	var tangent := Vector3.UP.cross(out)
	var k := clampf(r / PowerDefs.VORTEX_RADIUS, 0.0, 1.0)
	var speed := lerpf(PowerDefs.VORTEX_SPEED.x, PowerDefs.VORTEX_SPEED.y, k)
	# Keep pieces between the core and 90% of the radius, drifting slowly in.
	var target_r := clampf(r - 0.4, PowerDefs.VORTEX_CORE * 1.5, PowerDefs.VORTEX_RADIUS * 0.9)
	var radial := out * (target_r - r) * 2.0
	# Each piece keeps its own layer of the disc (thicker toward the edge).
	var target_y := center.y + layer * (1.0 + 3.0 * k)
	var vertical := Vector3.UP * (target_y - p.y) * 3.0
	return tangent * speed + radial + vertical


func _spin_debris(delta: float) -> void:
	var debris := _world.debris
	var r := PowerDefs.VORTEX_RADIUS
	var blend := clampf(5.0 * delta, 0.0, 1.0)
	caught = 0
	for i in debris.capacity:
		if not debris.is_active(i):
			continue
		var p := debris.position_of(i)
		if p.distance_to(center) > r:
			continue
		caught += 1
		var layer := fmod(float(i) * 0.6180339, 1.0) * 2.0 - 1.0
		var v := debris.velocity_of(i).lerp(_orbit_velocity(p, layer), blend)
		# Gravity is cancelled inside the storm.
		v.y += 18.0 * delta
		debris.set_velocity(i, v)
		debris.set_tint(i, 0.8)


func _spin_stones(delta: float) -> void:
	var blend := clampf(3.0 * delta, 0.0, 1.0)
	for node in get_tree().get_nodes_in_group("meteor_stone"):
		var stone := node as RigidBody3D
		var p := stone.global_position
		if p.distance_to(center) > PowerDefs.VORTEX_RADIUS:
			continue
		var layer := fmod(float(stone.get_instance_id() % 1000) * 0.6180339, 1.0) * 2.0 - 1.0
		var v := stone.linear_velocity.lerp(_orbit_velocity(p, layer), blend)
		v.y += 18.0 * delta
		stone.linear_velocity = v


## Pieces in the band are not pulled, they are ground down.
func _shred_band(dt: float) -> void:
	var debris := _world.debris
	var r := PowerDefs.VORTEX_RADIUS
	var outer := r + PowerDefs.VORTEX_BAND
	for i in debris.capacity:
		if not debris.is_active(i):
			continue
		var d := debris.position_of(i).distance_to(center)
		if d <= r or d > outer:
			continue
		if debris.size_of(i).length() > 0.7 and randf() < 0.5 * dt:
			debris.fracture(i)


func _hurt_player(dt: float) -> void:
	var player := _world.player
	if player == null:
		return
	var d := (player.global_position + Vector3(0, 0.9, 0)).distance_to(center)
	var r := PowerDefs.VORTEX_RADIUS
	if d < r:
		player.hurt(PowerDefs.VORTEX_HURT_INSIDE * dt, center)
	elif d < r + PowerDefs.VORTEX_BAND:
		player.hurt(PowerDefs.VORTEX_HURT_BAND * dt, center)


func _update_visuals() -> void:
	var r := PowerDefs.VORTEX_RADIUS
	var spin := PowerDefs.VORTEX_SPINUP
	var end := spin + PowerDefs.VORTEX_DURATION
	var grow := ease(clampf(_t / spin, 0.0, 1.0), 0.4)
	var fade := 1.0 - clampf((_t - end) / FADE, 0.0, 1.0)
	var k := grow * fade
	var wobble := 1.0 + sin(_t * 23.0) * 0.04
	_core.scale = Vector3.ONE * PowerDefs.VORTEX_CORE * k * wobble
	_shell.scale = Vector3.ONE * r * k
	_disc.scale = Vector3(r * 1.3 * k, 1, r * 1.3 * k)
	_disc.rotation.y -= get_physics_process_delta_time() * 2.5
	_ring_inner.scale = Vector3(r, 1, r) * maxf(k, 0.01)
	_ring_outer.scale = Vector3.ONE * (r + PowerDefs.VORTEX_BAND) * maxf(k, 0.01)
	_ring_outer.scale.y = 1.0
	_light.light_energy = 3.0 * k
	_inflow.emitting = fade > 0.5
