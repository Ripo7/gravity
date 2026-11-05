class_name Vortex
extends Node3D
## Black hole power. It opens where you aim and does not explode: everything
## inside its radius is torn loose and spins around the core like a storm.
## Just outside the radius is a band that is not pulled but shredded:
## blocks there crack and break, and it hurts you. When it closes, the
## spinning pieces spill out.

signal closed

const HALO_SHADER := preload("res://shaders/black_hole.gdshader")
const DISC_SHADER := preload("res://shaders/accretion.gdshader")
const HALO := 2.4  ## halo radius / core radius
const DISC := 3.6  ## accretion disc radius / core radius
const FADE := 0.6
const TICK := 0.1  ## seconds between damage passes
const RELEASE_SPIN := 0.25  ## share of orbit speed kept when it bursts
## Flung pieces pass through each other this long (s): the disc packs them
## closer than they fit, and colliding at once would stop them dead.
const SPREAD_TIME := 0.35

var center := Vector3.ZERO
var caught := 0  ## pieces currently orbiting
var _world: GameWorld
var _t := 0.0
var _tick := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _disc: MeshInstance3D
var _disc2: MeshInstance3D
var _ring_inner: MeshInstance3D
var _ring_outer: MeshInstance3D
var _light: OmniLight3D
var _inflow: CPUParticles3D
var _pull_started := false
var _flung := PackedInt32Array()
var _spread_until := 0.0


func setup(world: GameWorld, at: Vector3) -> void:
	_world = world
	center = at
	position = at


func _ready() -> void:
	add_to_group("vortex")
	var r := PowerDefs.VORTEX_RADIUS
	# The ball itself: pure black, opaque, so it hides what is behind it.
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	_core = Fx.sphere(1.0, black, 48)
	add_child(_core)
	var halo := ShaderMaterial.new()
	halo.shader = HALO_SHADER
	halo.set_shader_parameter("core_ratio", 1.0 / HALO)
	halo.set_shader_parameter("violet", Palette.VIOLET)
	_halo = Fx.sphere(1.0, halo, 48)
	add_child(_halo)
	_disc = _accretion(0.0)
	_disc2 = _accretion(PI * 0.5)
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


## A flat swirling ring around the core, tilted so it reads as a disc.
func _accretion(yaw: float) -> MeshInstance3D:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.001
	disc.radial_segments = 96
	disc.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = DISC_SHADER
	m.set_shader_parameter("violet", Palette.VIOLET)
	m.set_shader_parameter("inner", 1.05 / DISC)
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation = Vector3(0.28, yaw, 0.0)
	add_child(mi)
	return mi


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
	if _t >= PowerDefs.VORTEX_SPINUP + PowerDefs.VORTEX_DURATION and _pull_started and caught > 0:
		_release()
	if not _flung.is_empty() and _t >= _spread_until:
		_end_spread()
	if _t >= PowerDefs.VORTEX_SPINUP + PowerDefs.VORTEX_DURATION + FADE:
		_end_spread()
		closed.emit()
		queue_free()
		return
	if not is_pulling() or _world == null:
		return
	if not _pull_started:
		_pull_started = true
		Sfx.play("implode", center, 4.0, 0.7)
	_spin_debris(delta)
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


## Velocity that carries a piece at `p` to its next spot on the orbit in
## `dt`: around the vertical axis (faster near the core), easing toward its
## ring and its layer of the disc. Exact, so fast pieces never fly out.
func _orbit_velocity(p: Vector3, layer: float, lane: float, dt: float) -> Vector3:
	var off := p - center
	var flat := Vector3(off.x, 0, off.z)
	var r := flat.length()
	if r < 0.05:
		flat = Vector3.RIGHT * 0.05
		r = 0.05
	var k := clampf(r / PowerDefs.VORTEX_RADIUS, 0.0, 1.0)
	var omega := lerpf(PowerDefs.VORTEX_SPIN.x, PowerDefs.VORTEX_SPIN.y, k)
	omega = minf(omega, PowerDefs.VORTEX_MAX_SPEED / r)
	# Each piece settles on its own lane, from just outside the ball to 85%
	# of the radius, so the whole disc fills up.
	var target_r := lerpf(PowerDefs.VORTEX_CORE * 1.7, PowerDefs.VORTEX_RADIUS * 0.85, lane)
	var next_r := move_toward(r, target_r, 4.0 * dt)
	var next_flat := (flat / r).rotated(Vector3.UP, omega * dt) * next_r
	# Each piece keeps its own layer of the disc (thicker toward the edge).
	var target_y := center.y + layer * (0.8 + 3.0 * k)
	var next_y := lerpf(p.y, target_y, clampf(4.0 * dt, 0.0, 1.0))
	var next := Vector3(center.x + next_flat.x, next_y, center.z + next_flat.z)
	return (next - p) / dt


func _spin_debris(delta: float) -> void:
	var debris := _world.debris
	var r := PowerDefs.VORTEX_RADIUS
	caught = 0
	for i in debris.capacity:
		if not debris.is_active(i):
			continue
		var p := debris.position_of(i)
		if p.distance_to(center) > r:
			if debris.in_storm(i):
				debris.set_storm(i, false)
			continue
		caught += 1
		debris.set_storm(i, true)
		var layer := fmod(float(i) * 0.6180339, 1.0) * 2.0 - 1.0
		var lane := fmod(float(i) * 0.7548777, 1.0)
		var want := _orbit_velocity(p, layer, sqrt(lane), delta)
		# Newly caught pieces are swept up quickly, then held exactly.
		var v := debris.velocity_of(i).lerp(want, 0.35)
		# Gravity is cancelled inside the storm.
		v.y += 18.0 * delta
		debris.set_velocity(i, v)
		debris.set_tint(i, 0.8)


## The storm ends in a burst: everything it held is flung outward (faster
## from near the core), with a little lift and some of its swirl.
func _release() -> void:
	caught = 0
	if _world == null:
		return
	var debris := _world.debris
	var r := PowerDefs.VORTEX_RADIUS
	var flung := 0
	for i in debris.capacity:
		if not (debris.is_active(i) and debris.in_storm(i)):
			continue
		_flung.append(i)
		var off := debris.position_of(i) - center
		var flat := Vector3(off.x, 0, off.z)
		var dir := (
			flat.normalized() if flat.length() > 0.05 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
		)
		var k := clampf(flat.length() / r, 0.0, 1.0)
		var speed := lerpf(PowerDefs.VORTEX_BURST_SPEED.x, PowerDefs.VORTEX_BURST_SPEED.y, k)
		speed *= randf_range(0.8, 1.15)
		var v := dir * speed + Vector3.UP * (PowerDefs.VORTEX_BURST_LIFT + off.y * 1.5)
		debris.set_velocity(i, v + debris.velocity_of(i) * RELEASE_SPIN)
		debris.add_spin(i, Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 8.0)
		debris.set_tint(i, 1.0)
		flung += 1
	_spread_until = _t + SPREAD_TIME
	if flung > 0:
		Sfx.play("burst", center, 2.0 + minf(flung, 80) * 0.05, 0.8)
		if _world.dust:
			_world.dust.puff(center, r * 0.6, Materials.Kind.CONCRETE, 12)
		for s in get_tree().get_nodes_in_group("camera_shake"):
			(s as CameraShake).add_trauma(0.25 + minf(flung, 100) * 0.003)


## The flung pieces collide with each other (and land) again.
func _end_spread() -> void:
	if _world != null:
		for i in _flung:
			if _world.debris.is_active(i):
				_world.debris.set_storm(i, false)
	_flung.clear()


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
		if debris.volume_of(i) > 0.08 and randf() < 0.5 * dt:
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
	var pulse := 1.0 + sin(_t * 17.0) * 0.03
	var core := PowerDefs.VORTEX_CORE * k * pulse
	_core.scale = Vector3.ONE * maxf(core, 0.001)
	_halo.scale = Vector3.ONE * maxf(core * HALO, 0.001)
	_disc.scale = Vector3(core * DISC, 1, core * DISC)
	_disc2.scale = Vector3(core * DISC * 0.8, 1, core * DISC * 0.8)
	# The second, fainter disc is the far side bent over the top by the lens.
	(_disc2.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.35)
	(_disc.material_override as ShaderMaterial).set_shader_parameter("intensity", k)
	_ring_inner.scale = Vector3(r, 1, r) * maxf(k, 0.01)
	_ring_outer.scale = Vector3.ONE * (r + PowerDefs.VORTEX_BAND) * maxf(k, 0.01)
	_ring_outer.scale.y = 1.0
	_light.light_energy = 3.0 * k
	_inflow.emitting = fade > 0.5
