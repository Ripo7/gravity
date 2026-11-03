class_name BlastParams
extends RefCounted
## Everything about a gravity blast derived from one charge value (0..1).
## Kept in one place so tuning is easy and the scaling is unit-tested.

const MIN_CHARGE := 0.08

var charge: float
var radius: float  ## metres, reach of pull and burst
var core_radius: float  ## pieces inside are held, not accelerated further
var pull_time: float  ## seconds of black-hole phase
var pull_accel: float  ## m/s^2 toward the core at the centre
var burst_speed: float  ## m/s added outward at the centre
var damage: float  ## structural damage at the centre
var break_radius: float  ## metres within which blocks take damage
var ball_radius: float  ## visual/collision radius of the thrown ball
var throw_speed: float
var shake: float  ## 0..1 camera trauma added near the blast
var slow_motion: bool


static func from_charge(c: float) -> BlastParams:
	var p := BlastParams.new()
	p.charge = clampf(c, MIN_CHARGE, 1.0)
	var k := p.charge
	var k2 := k * k
	p.radius = lerpf(3.0, 13.0, k)
	p.core_radius = lerpf(0.5, 1.6, k)
	p.pull_time = lerpf(0.28, 0.85, k)
	p.pull_accel = lerpf(40.0, 120.0, k)
	p.burst_speed = lerpf(8.0, 24.0, k)
	p.damage = lerpf(2.0, 11.0, k2)
	# Damage reaches much less far than the pull: aiming matters.
	p.break_radius = lerpf(1.3, 4.2, k)
	p.ball_radius = lerpf(0.1, 0.42, k)
	p.throw_speed = lerpf(36.0, 26.0, k)
	p.shake = lerpf(0.25, 1.0, k)
	p.slow_motion = k >= 0.6
	return p


## 1 at the centre, 0 at the radius, smooth in between.
func falloff(distance: float) -> float:
	return _smooth(distance, radius)


## Structural damage falloff (shorter reach than the pull).
func break_falloff(distance: float) -> float:
	return _smooth(distance, break_radius)


static func _smooth(distance: float, reach: float) -> float:
	if distance >= reach:
		return 0.0
	var t := 1.0 - distance / reach
	return t * t * (3.0 - 2.0 * t)
