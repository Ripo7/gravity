class_name Matter
extends RefCounted
## What things are made of. The matter of a piece alone says how the piece
## answers a blow (docs/CONCEPT.md). Two so far.
##
## Concrete cracks for all to see, then lets go: it breaks into a few big,
## heavy blocks. It carries: what stood on a piece of it comes down when the
## piece is gone.
##
## Metal bends and keeps the shape: each blow bends it a little more, away
## from the blow (a blow from the other side straightens it). It never
## breaks. Bent as far as it goes, it lies down, in one piece, and what it
## carried comes down.

enum { CONCRETE, METAL }

## The paint of each, in greybox.
const TINT: Array[Color] = [Color(0.68, 0.68, 0.66), Color(0.33, 0.42, 0.56)]
## kg/m3.
const DENSITY: Array[float] = [2400.0, 7800.0]
## How much a piece takes before it lets go (concrete) or lies down (metal),
## in points of blows, for each metre it is thick the way it is thinnest. A
## blow is 2 points, a heavy one (the last of the combination, the kick) 3.
## A concrete column 0.4 m thick takes 9, one whole combination; a metal
## post 0.2 m thick takes 14, a combination and a half. It belongs to the
## piece: however the piece is cut or drawn, it gives at the same blow.
const STRENGTH: Array[float] = [22.5, 70.0]
## Does it bend (and never break), or break into blocks?
const BENDS: Array[bool] = [false, true]
## What breaks, breaks into blocks about this big (m), bigger if that would
## make more than MOST_BLOCKS of them: a few big blocks, whatever the piece.
const BLOCK := 0.7
const MOST_BLOCKS := 9
## What bends is drawn as rings across it, RING m apart at most, that the
## bend moves. The bend is where the first blow landed, spread over KINK m
## of the piece. Bent as far as it goes, a piece that stands free leans
## BEND_MOST rad from there up; one that carries something keeps its head
## where it is and bows BOW_MOST m aside instead.
const RING := 0.3
const KINK := 1.0
const BEND_MOST := 1.25
const BOW_MOST := 0.55


## How many points of blows a piece of `of`, `size` across, takes.
static func strength(of: int, size: Vector3) -> float:
	return STRENGTH[of] * minf(size.x, minf(size.y, size.z))


## How big (m) the blocks of a piece that breaks, `size` across, are cut.
static func grain(size: Vector3) -> float:
	var across := BLOCK
	while _cells(size, across) > MOST_BLOCKS:
		across *= 1.1
	return across


## How many rings a piece that bends, `size` across, is drawn with: as many
## as its height takes if it stands upright, its two ends if it lies flat (a
## plate bends no way a blow could send it).
static func rings(size: Vector3) -> int:
	return maxi(2, ceili(size.y / RING) + 1) if upright(size) else 2


## Does a piece `size` across stand upright (as high as it is wide, or
## higher)?
static func upright(size: Vector3) -> bool:
	return size.y >= maxf(size.x, size.z)


## How many blocks a piece `size` across is cut into, about `across` each.
static func _cells(size: Vector3, across: float) -> int:
	var cells := 1
	for axis in 3:
		cells *= maxi(1, roundi(size[axis] / across))
	return cells
