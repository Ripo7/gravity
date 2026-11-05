class_name Hazards
extends RefCounted
## What hurts: turns a physics body that touched something into a mass and a
## velocity, and a hit into damage. Shared by the player and the shield.

## Momentum (kg·m/s, counted above MIN_SPEED) that does no damage.
const SAFE_MOMENTUM := 10.0
## Momentum per point of damage above the safe level.
const MOMENTUM_PER_HP := 4.0
## Closing speed (m/s) below which nothing hurts (resting, sliding, rolling).
## You are fragile: a brick at running speed takes half your health.
const MIN_SPEED := 2.5


## {mass, velocity} for a debris piece or a falling structure piece; empty
## if `rid` is neither (or is a shard of black ice).
static func motion_of(world: GameWorld, rid: RID, body: Object) -> Dictionary:
	if world == null or body is RigidBody3D:
		return {}
	var i := world.debris.index_of(rid)
	if i >= 0:
		# Your own shield's shards never hurt you (or wear another shield).
		if world.debris.kind_of(i) == Materials.Kind.ICE:
			return {}
		# Nor do the pieces your own black hole just flung (they glow).
		if world.debris.tint_of(i) > 0.3:
			return {}
		return {"mass": world.debris.mass_of(i), "velocity": world.debris.recent_velocity_of(i)}
	return world.structures.cluster_motion(rid)


## Damage to the player from something of `mass` closing at `speed`.
static func damage_for(mass: float, speed: float) -> float:
	if speed < MIN_SPEED:
		return 0.0
	return clampf((mass * (speed - MIN_SPEED) - SAFE_MOMENTUM) / MOMENTUM_PER_HP, 0.0, 250.0)
