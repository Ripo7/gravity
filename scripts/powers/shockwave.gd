class_name Shockwave
extends Node3D
## Shock wave power: a blast of air out of your hands, along where you look.
## Its front runs out to SHOCK_RANGE in a cone. What it passes is thrown
## away from you (loose pieces, falling pieces of building), and standing
## blocks take a hit that fades with distance: close, it punches through a
## wall; far, it only knocks loose what was barely holding. You see the
## front go (a cap of bent air) and dust kicked up off the ground under it.

## The front is dealt with in steps of at least this many metres.
const STEP := 1.0
## Dust kicked up off the ground every this many metres of the front.
const DUST_EVERY := 4.0
## After the front the air goes on rushing out for WIND seconds, carrying
## the dust off (what it breaks raises a cloud right in front of you).
const WIND := 1.8
const WIND_SPEED := 18.0  ## m/s of push a second, at the start
## The colour of the rim of bent air.
const AIR := Color(0.85, 0.92, 1.0)

var origin := Vector3.ZERO
var direction := Vector3.FORWARD
var _world: GameWorld
var _front := 0.0  # how far the front has gone (m)
var _done := 0.0  # how far it has been dealt with
var _next_dust := 1.5
var _cos := 0.0
var _ground := 0.0
var _t := 0.0


## `at`: where it leaves your hands; `dir`: where you look; `ground`: the
## height of the floor under you.
func setup(world: GameWorld, at: Vector3, dir: Vector3, ground: float) -> void:
	_world = world
	origin = at
	direction = dir.normalized()
	_ground = ground


func _ready() -> void:
	add_to_group("shockwave")
	_cos = cos(deg_to_rad(PowerDefs.SHOCK_ANGLE))
	var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.BACK
	var xf := Transform3D(Basis.looking_at(direction, up), origin)
	var time := PowerDefs.SHOCK_RANGE / PowerDefs.SHOCK_SPEED
	var wave := BlastWave.spawn(
		self, xf, 0.5, PowerDefs.SHOCK_RANGE, time * 1.5, AIR, PowerDefs.SHOCK_ANGLE + 6.0
	)
	(wave.material_override as ShaderMaterial).set_shader_parameter("glow", 1.4)
	var streaks := Fx.make_streaks(int(Quality.pick(24, 36, 48)), PowerDefs.SHOCK_ANGLE)
	add_child(streaks)
	streaks.global_transform = xf
	streaks.emitting = true
	Sfx.play("burst", origin, 3.0, 1.3)
	var cam := get_viewport().get_camera_3d() as CameraShake
	if cam:
		cam.add_trauma(0.3)


func _physics_process(delta: float) -> void:
	_t += delta
	_front = minf(_front + PowerDefs.SHOCK_SPEED * delta, PowerDefs.SHOCK_RANGE)
	while _front >= _next_dust and _next_dust < PowerDefs.SHOCK_RANGE:
		_kick_dust(_next_dust)
		_next_dust += DUST_EVERY
	if _world and (_front - _done >= STEP or _front >= PowerDefs.SHOCK_RANGE) and _done < _front:
		_hit(_done, _front)
		_done = _front
	if _world and _world.dust:
		var gust := WIND_SPEED * delta * clampf(1.0 - _t / WIND, 0.0, 1.0)
		_world.dust.blow(origin, direction, _cos * 0.9, 0.0, _front, gust)
	if _t > maxf(PowerDefs.SHOCK_RANGE / PowerDefs.SHOCK_SPEED * 1.5 + 0.1, WIND):
		queue_free()


## How hard it hits at distance `d` (1 at your hands, 0 at the end).
static func strength(d: float) -> float:
	return pow(clampf(1.0 - d / PowerDefs.SHOCK_RANGE, 0.0, 1.0), 1.5)


## True when world point `p` is in the cone, `d` away from where it left.
func in_cone(p: Vector3) -> bool:
	var off := p - origin
	var d := off.length()
	return d < 0.5 or off.dot(direction) >= d * _cos


## Everything between `near` and `far` metres out takes the blast.
func _hit(near: float, far: float) -> void:
	var debris := _world.debris
	debris.thaw_near(origin + direction * (near + far) * 0.5, (far - near) * 0.5 + far * 0.6)
	for i in debris.slot_end():
		if not debris.is_active(i):
			continue
		var p := debris.position_of(i)
		var d := p.distance_to(origin)
		if d > far or d <= near or not in_cone(p):
			continue
		var f := strength(d)
		var away := (p - origin).normalized()
		# Heavy pieces are moved less than light ones.
		var heft := 1.0 / (1.0 + debris.volume_of(i) * 0.8)
		var kick := (away * PowerDefs.SHOCK_PUSH + Vector3.UP * PowerDefs.SHOCK_LIFT) * f * heft
		debris.set_velocity(i, debris.velocity_of(i) + kick)
		debris.add_spin(i, Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 10.0 * f)
	_world.structures.blast(origin, direction, _cos, near, far, PowerDefs.SHOCK_DAMAGE)
	_world.structures.push_clusters(origin, direction, _cos, near, far, PowerDefs.SHOCK_PUSH * 0.5)
	if _world.dust:
		_world.dust.blow(origin, direction, _cos, near, far, PowerDefs.SHOCK_PUSH * 0.6)


## A puff of dust off the floor (or the heap) under the front.
func _kick_dust(d: float) -> void:
	if _world == null or _world.dust == null:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.2:
		return
	var p := origin + flat.normalized() * d
	var floor_y := _ground
	if _world.rubble:
		floor_y = maxf(floor_y, _world.rubble.height_at(p))
	# Only if the front sweeps low enough over the floor to stir it.
	var front := origin + direction * d
	if front.y - floor_y > 2.5 + d * tan(deg_to_rad(PowerDefs.SHOCK_ANGLE)):
		return
	p.y = floor_y + 0.2
	# Low and light: a veil swept off the floor, not a cloud in your face.
	_world.dust.puff(p, 0.5 + d * 0.06, Materials.Kind.CONCRETE, 5)
