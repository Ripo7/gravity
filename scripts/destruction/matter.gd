class_name Matter
extends RefCounted
## What things are made of. The matter of a piece alone says how the piece
## answers a blow (docs/CONCEPT.md). One so far.
##
## Concrete cracks for all to see, then lets go: it breaks into a few big,
## heavy blocks that drop where they are. It carries: what stood on a piece
## of it comes down when the piece is gone.

enum { CONCRETE }

## The paint of each, in greybox.
const TINT: Array[Color] = [Color(0.68, 0.68, 0.66)]
## kg/m3.
const DENSITY: Array[float] = [2400.0]
## How much a piece takes before it lets go, in points of blows, for each
## metre it is thick the way it is thinnest. A blow is 2 points, a heavy one
## (the last of the combination, the kick) 3: a column 0.4 m thick takes 9,
## one whole combination. It belongs to the piece: however the piece is cut
## into blocks, it lets go at the same blow.
const STRENGTH: Array[float] = [22.5]
## A piece breaks into blocks about this big (m), bigger if that would make
## more than MOST_BLOCKS of them: a few big blocks, whatever the piece.
const BLOCK: Array[float] = [0.7]
const MOST_BLOCKS: Array[int] = [9]


## How many points of blows a piece of `of`, `size` across, takes.
static func strength(of: int, size: Vector3) -> float:
	return STRENGTH[of] * minf(size.x, minf(size.y, size.z))


## How big (m) the blocks of a piece of `of`, `size` across, are cut.
static func grain(of: int, size: Vector3) -> float:
	var across := BLOCK[of]
	while _cells(size, across) > MOST_BLOCKS[of]:
		across *= 1.1
	return across


## How many blocks a piece `size` across is cut into, about `across` each.
static func _cells(size: Vector3, across: float) -> int:
	var cells := 1
	for axis in 3:
		cells *= maxi(1, roundi(size[axis] / across))
	return cells
