class_name Matter
extends RefCounted
## What things are made of. The matter of a piece alone says how the piece
## answers a blow (docs/CONCEPT.md). Three so far.
##
## Concrete cracks where it is struck, for all to see, then lets go there:
## the few big, heavy blocks round the place are knocked out. It carries:
## what stood on it comes down when what was under it is gone.
##
## Metal bends and keeps the shape: each blow leaves its mark where it
## lands, a dent in a sheet, a kink in a post, away from the blow (a blow
## from the other side takes as much back). It never breaks. Marked as
## deep as it goes in one place, it lies down, in one piece, and what it
## carried comes down. (See Bend.)
##
## Wood snaps clean where it is struck, at the first blow: the length of
## it the blow lands on goes as small wood, and what was beyond it is cut
## off in one, long and light, and thrown far. It is cut along its grain,
## across the way it is longest. It carries. On the ground it stays in
## long pieces; struck again, one comes apart into small wood.

enum { CONCRETE, METAL, WOOD }

## The paint of each, in greybox.
const TINT: Array[Color] = [Color(0.68, 0.68, 0.66), Color(0.33, 0.42, 0.56), Color(0.74, 0.56, 0.34)]
## kg/m3.
const DENSITY: Array[float] = [2400.0, 7800.0, 600.0]
## How much a piece takes before it lets go (concrete) or lies down (metal),
## in points of blows, for each metre it is thick the way it is thinnest. A
## blow is 2 points, a heavy one (the last of the combination, the kick) 3.
## A concrete column 0.4 m thick takes 9, one whole combination; a metal
## post 0.2 m thick takes 14, a combination and a half. It belongs to the
## piece: however the piece is cut or drawn, it gives at the same blow.
## (Metal takes it in one place: blows elsewhere start another mark.)
## Wood gives at the first blow, whatever it is: a post 0.2 m thick takes
## 1.6, less than a blow.
const STRENGTH: Array[float] = [22.5, 70.0, 8.0]
## Does it bend (and never break), or break into blocks?
const BENDS: Array[bool] = [false, true, false]
## A place is this far across (m) each way from where it was first struck:
## a blow nearer than this to a place already struck adds to it, and when
## the place gives, the blocks whose middle is within this of it go (the
## nearest, at least). Concrete loses what is round the fist; wood, the
## length of it the blow lands on.
const PLACE: Array[float] = [0.45, 0.0, 0.22]
## Blocks are knocked out at this speed (m/s, as at real gravity).
const KNOCK: Array[float] = [3.5, 0.0, 6.0]
## What a blow cuts off from the rest of a piece is thrown at this speed
## (m/s, as at real gravity) along the blow, on top of going over.
## Concrete only goes over.
const THROWN: Array[float] = [0.0, 0.0, 5.5]
## Does what comes down in one break into its blocks when it lands?
const SHATTERS: Array[bool] = [true, false, false]
## What breaks is cut into blocks. An upright piece (a wall, a column)
## takes blows: its blocks are about BLOCK m across, small enough for what
## a blow knocks out to be round the fist. A piece that lies flat (a slab)
## only comes down: its blocks are about SLAB_BLOCK m across. Bigger, both,
## if that would make more than MOST_BLOCKS of them.
const BLOCK := 0.4
const SLAB_BLOCK := 0.9
const MOST_BLOCKS := 60
## Wood is cut into lengths of about LENGTH m, whichever way it lies.
const LENGTH := 0.4
## A post that bends is drawn as rings across it, RING m apart at most,
## that a kink moves. It kinks at the height it is struck at, over KINK m
## of its length; a blow nearer than KINK_APART m to a kink it has already
## deepens that one, and it has KINKS of them at most. Kinked as far as it
## goes, a post that stands free leans BEND_MOST rad from there up; one
## that carries something keeps its head where it is and bows BOW_MOST m
## aside instead.
const RING := 0.3
const KINK := 1.0
const KINK_APART := 0.5
const KINKS := 3
const BEND_MOST := 1.25
const BOW_MOST := 0.55
## An upright piece wider than this (m) is a sheet, not a post: a fist
## does not kink it, it dents it. It is drawn as nodes NODE m apart at
## most; a blow pushes those within DENT_WIDE m of it in, by DENT m a
## point under the fist and less farther off.
const SLENDER := 0.5
const NODE := 0.2
const DENT := 0.06
const DENT_WIDE := 0.55
## A plate (a piece that lies flat) is made of triangles, two to a square
## about CELL m across, that fold along the lines between them.
const CELL := 1.8
## How hard metal is to fold: the turning force (N.m, at real gravity) a
## fold holds for each metre it is long and each metre squared its piece
## is thick. Under more it gives, slowly, and stays as it ends up. A post
## 0.2 m thick holds 3600 N.m at a kink: more than its own weight makes
## as it lies down, less than what it carried makes once it is kinked.
const FOLD := 450000.0


## How many points of blows a piece of `of`, `size` across, takes.
static func strength(of: int, size: Vector3) -> float:
	return STRENGTH[of] * minf(size.x, minf(size.y, size.z))


## How big (m) the blocks of a piece of `of` that breaks, `size` across,
## are cut.
static func grain(of: int, size: Vector3) -> float:
	if of == WOOD:
		return LENGTH
	var across := BLOCK if upright(size) else SLAB_BLOCK
	while _cells(size, across) > MOST_BLOCKS:
		across *= 1.1
	return across


## Does a piece `size` across stand upright (a column, a wall, a sheet),
## or lie flat (a slab, a deck: thinnest from top to bottom)?
static func upright(size: Vector3) -> bool:
	return size.y > minf(size.x, size.z)


## How many blocks a piece `size` across is cut into, about `across` each.
static func _cells(size: Vector3, across: float) -> int:
	var cells := 1
	for axis in 3:
		cells *= maxi(1, roundi(size[axis] / across))
	return cells
