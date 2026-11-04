class_name GravityBlast
extends Node3D
## A gravity explosion: a short black-hole pull, then an outward burst.
##
## Phase 1 (pull): blocks in range are broken or knocked loose, then every
## loose piece is accelerated toward the core with a slight swirl and held
## there by drag. Phase 2 (burst): a second damage pass, then every piece in
## range gets an outward kick that scales with the charge.

signal burst

enum Phase { PULL, BURST, DONE }

const SWIRL := 0.6
const PLAYER_PULL := 0.1
const PLAYER_BURST := 0.45
const LINGER := 0.8
const SHIELD_DAMAGE := 500.0
const HURT_REACH := 0.35  ## fraction of the blast radius that hurts
const HURT_MAX := 85.0

var params: BlastParams
var phase := Phase.PULL
var pieces_affected := 0
## Horizontal direction the ball was flying: the burst drives things this way.
var direction := Vector3.ZERO
var _t := 0.0
var _world: GameWorld


func setup(world: GameWorld, p: BlastParams, at: Vector3, travel := Vector3.ZERO) -> void:
	_world = world
	params = p
	position = at
	var flat := Vector3(travel.x, 0, travel.z)
	direction = flat.normalized() if flat.length() > 0.1 else Vector3.ZERO


func _ready() -> void:
	_world.structures.apply_blast(global_position, params, 1.0)


func _physics_process(delta: float) -> void:
	_t += delta
	match phase:
		Phase.PULL:
			_pull(delta)
			if _t >= params.pull_time:
				_burst()
		Phase.BURST:
			if _t >= params.pull_time + LINGER:
				phase = Phase.DONE
				queue_free()


func _pull(delta: float) -> void:
	var c := global_position
	var debris := _world.debris
	var r := params.radius
	var hold := params.core_radius
	pieces_affected = 0
	# Ease the pull in so pieces visibly lift and lean before they rush in.
	var ramp := lerpf(0.3, 1.0, smoothstep(0.0, 0.4, _t / params.pull_time))
	for i in debris.capacity:
		if not debris.is_active(i):
			continue
		var to_core := c - debris.position_of(i)
		var d := to_core.length()
		if d > r or d < 0.001:
			continue
		pieces_affected += 1
		var dir := to_core / d
		var v := debris.velocity_of(i)
		# Strong across the whole radius, gentle fade at the edge.
		var strength := params.pull_accel * sqrt(1.0 - d / r) * ramp
		var swirl := dir.cross(Vector3.UP).normalized() * SWIRL
		if d > hold:
			v += (dir + swirl) * strength * delta * debris.response_of(i)
		# Drag grows near the core so pieces cluster instead of overshooting.
		var drag := clampf((1.0 - d / r) * 5.0 * delta, 0.0, 0.5)
		v *= 1.0 - drag
		# Cancel gravity inside the field so things float up into the ball.
		v.y += 18.0 * delta * (1.0 - d / r)
		debris.set_velocity(i, v)
		# Tumble as they fall in; helps read the motion on small pieces.
		var tumble := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
		debris.add_spin(i, tumble * 14.0 * delta)
		debris.set_tint(i, 0.6 + 0.4 * (1.0 - d / r))
	# Meteor stones get dragged in too (they are heavy: half strength).
	for node in get_tree().get_nodes_in_group("meteor_stone"):
		var stone := node as RigidBody3D
		var to_core := c - stone.global_position
		var d := to_core.length()
		if d < r and d > hold:
			stone.linear_velocity += to_core / d * params.pull_accel * 0.5 * sqrt(1.0 - d / r) * ramp * delta
	_push_player(PLAYER_PULL * delta * params.pull_accel, true)


func _burst() -> void:
	phase = Phase.BURST
	var c := global_position
	var debris := _world.debris
	_world.structures.apply_blast(c, params, 0.6)
	var big: Array[int] = []
	for i in debris.capacity:
		if not debris.is_active(i):
			continue
		var d := debris.position_of(i).distance_to(c)
		if d < params.radius * 0.5 and debris.size_of(i).length() > 0.9:
			big.append(i)
	# Large whole blocks near the core shatter before being thrown.
	for i in big:
		if params.damage * params.break_falloff(debris.position_of(i).distance_to(c)) > 2.0:
			debris.fracture(i)
	pieces_affected = 0
	for i in debris.capacity:
		if not debris.is_active(i):
			continue
		var offset := debris.position_of(i) - c
		var d := offset.length()
		if d > params.radius:
			continue
		pieces_affected += 1
		var dir := offset / d if d > 0.01 else Vector3.UP
		dir = (dir + Vector3.UP * 0.35).normalized()
		var f := maxf(params.falloff(d), 0.15)
		var jitter := randf_range(0.75, 1.25)
		var kick := params.burst_speed * f * jitter * debris.response_of(i)
		debris.set_velocity(i, debris.velocity_of(i) * 0.2 + dir * kick)
		debris.add_spin(i, Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 10.0 * f)
		debris.set_tint(i, 1.0)
	_world.structures.push_clusters(c, params.radius * 1.2, params.burst_speed * 0.6, direction)
	for node in get_tree().get_nodes_in_group("meteor_stone"):
		var stone := node as RigidBody3D
		var off := stone.global_position - c
		var d := off.length()
		if d < params.radius and d > 0.01:
			stone.linear_velocity += (
				(off / d + Vector3.UP * 0.3).normalized() * params.burst_speed * 0.5 * params.falloff(d)
			)
	for node in get_tree().get_nodes_in_group("ice_shield"):
		var shield := node as IceShield
		var d := shield.global_position.distance_to(c)
		if d < params.radius:
			shield.hit(SHIELD_DAMAGE * params.charge * params.falloff(d))
	_push_player(PLAYER_BURST * params.burst_speed, false)
	_hurt_player()
	burst.emit()


## Standing too close to your own singularity when it bursts hurts.
func _hurt_player() -> void:
	var player := _world.player
	if player == null:
		return
	var reach := params.radius * HURT_REACH
	var d := player.global_position.distance_to(global_position)
	if d < reach:
		var k := 1.0 - d / reach
		player.hurt(HURT_MAX * k * (0.5 + 0.5 * params.charge), global_position)


func _push_player(amount: float, toward: bool) -> void:
	var player := _world.player
	if player == null:
		return
	var offset := player.global_position - global_position
	var d := offset.length()
	if d > params.radius or d < 0.01:
		return
	var dir := offset / d * (-1.0 if toward else 1.0)
	player.add_impulse(dir * amount * params.falloff(d))
