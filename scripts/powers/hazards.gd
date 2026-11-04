class_name Hazards
extends RefCounted
## What hurts: turns a physics body that touched something into a mass and a
## velocity, and a hit into damage. Shared by the player and the shield.

## Momentum (kg·m/s, counted above MIN_SPEED) that does no damage.
const SAFE_MOMENTUM := 150.0
## Momentum per point of damage above the safe level.
const MOMENTUM_PER_HP := 25.0
## Closing speed (m/s) below which nothing hurts (resting, sliding, rolling).
const MIN_SPEED := 4.5


## {mass, velocity} for a debris piece, a falling structure piece or a
## meteor stone; empty if `rid` is none of those.
static func motion_of(world: GameWorld, rid: RID, body: Object) -> Dictionary:
	if body is MeteorStone:
		var s := body as MeteorStone
		return {"mass": s.mass, "velocity": s.linear_velocity}
	if world == null:
		return {}
	var i := world.debris.index_of(rid)
	if i >= 0:
		return {"mass": world.debris.mass_of(i), "velocity": world.debris.velocity_of(i)}
	return world.structures.cluster_motion(rid)


## Damage to the player from something of `mass` closing at `speed`.
static func damage_for(mass: float, speed: float) -> float:
	if speed < MIN_SPEED:
		return 0.0
	return clampf((mass * (speed - MIN_SPEED) - SAFE_MOMENTUM) / MOMENTUM_PER_HP, 0.0, 250.0)
