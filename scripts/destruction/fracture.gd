class_name Fracture
extends RefCounted
## Pre-computed fracture patterns.
##
## A block is cut by recursive random planes along its longest axis
## (a "BSP" fracture). Every piece is an axis-aligned box inside the block,
## so the pieces tile the block exactly, collide as cheap box shapes in Jolt
## and all render through one shared box mesh (one draw call).
## Patterns are cached per block size, so after warm-up a break costs only
## a dictionary lookup.

## Pieces smaller than this along any axis are not split further.
const MIN_EDGE := 0.14

static var _cache := {}


## Returns an Array of AABBs centred on the block origin, covering a box of
## `size`. `pieces` is the target piece count; `seed_value` picks the pattern.
static func pattern(size: Vector3, pieces: int, seed_value: int = 0) -> Array[AABB]:
	var key := "%s|%d|%d" % [size.snappedf(0.001), pieces, seed_value]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var result: Array[AABB] = [AABB(-size * 0.5, size)]
	# Repeatedly split the largest piece: gives a natural mix of sizes.
	while result.size() < pieces:
		var idx := _largest(result)
		var box: AABB = result[idx]
		var axis := _longest_axis(box.size)
		var edge: float = box.size[axis]
		if edge < MIN_EDGE * 2.0:
			break
		var t := rng.randf_range(0.3, 0.7)
		var a := box
		var b := box
		a.size[axis] = edge * t
		b.position[axis] = box.position[axis] + edge * t
		b.size[axis] = edge * (1.0 - t)
		result[idx] = a
		result.append(b)
	_cache[key] = result
	return result


## Suggested piece count for a block: bigger blocks break into more pieces.
static func piece_count_for(size: Vector3) -> int:
	var volume := size.x * size.y * size.z
	return clampi(int(round(volume * 14.0)), 3, 14)


static func clear_cache() -> void:
	_cache.clear()


static func _largest(boxes: Array[AABB]) -> int:
	var best := 0
	var best_volume := -1.0
	for i in boxes.size():
		var v := boxes[i].get_volume()
		if v > best_volume:
			best_volume = v
			best = i
	return best


static func _longest_axis(s: Vector3) -> int:
	if s.x >= s.y and s.x >= s.z:
		return 0
	if s.y >= s.z:
		return 1
	return 2
