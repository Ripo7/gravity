class_name FallingCluster
extends RefCounted
## A falling piece of a structure: one rigid body with a box per block.
## StructureSet owns the blocks; this is their shared body while they fall.

var body: RID
var members := PackedInt32Array()
var offsets: Array[Transform3D] = []  # block transform in body space
var mass := 0.0
var age := 0.0
var prev_velocity := Vector3.ZERO
var recent := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # last speeds
var toppled := false  # pivoting over its base: falls toward the cut side
var lean_time := 0.0  # seconds resting against a standing structure
var leaned := false
var crush_tick := 0.0


func transform() -> Transform3D:
	return PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)


## Bounds of the block centres at `xf`, grown by 1 m.
func bounds(xf: Transform3D) -> AABB:
	var box := AABB((xf * offsets[0]).origin, Vector3.ZERO)
	for off in offsets:
		box = box.expand((xf * off).origin)
	return box.grow(1.0)


func lowest_point(xf: Transform3D) -> Vector3:
	var best := Vector3(0, INF, 0)
	for off in offsets:
		var p := xf * off.origin
		if p.y < best.y:
			best = p
	return best


## World position of the block centre nearest to `p`.
func nearest_point(p: Vector3) -> Vector3:
	var xf := transform()
	var best := Vector3.INF
	var best_d := INF
	for off in offsets:
		var q := xf * off.origin
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best
