class_name City
extends RefCounted
## A toy city for two giants, made up from a number: the same number gives
## the same city, another number another one. The brutes keep their size and
## the city is small around them, about a tenth of a real one: houses come
## up to their knees, offices to their heads, towers stand three times as
## high as they do.
##
## How it is made up. Streets a few metres apart, never evenly, cut the
## ground into three or four rows of three or four blocks. One block that
## is not on the edge is left empty: the square, where the fight starts (its
## middle is the middle of the world). Every other block is a district:
## downtown, houses or a park, downtown more often next to the square. A
## block is cut into lots, and each lot gets what its district puts there:
## a tower, an office, a few houses, trees. Then cars along the avenues and
## on them, trees round the square, and in most cities a railway on stilts
## down one avenue, with a train on it.
##
## It is planned as a list of boxes before anything is built, and planned
## again with less in it for as long as it would be cut into more shards
## than a phone carries (MOST).
##
## What is lower than Fighter.WADE (the houses, the cars, the trees, the
## railway) a brute walks through; the rest it has to break. Structure cuts
## the boxes into shards.

## What a block is.
enum { SQUARE, DOWNTOWN, HOUSES, PARK }

## Blocks are BLOCK_LEAST to BLOCK_MOST m across (the square SQUARE_LEAST at
## least), avenues AVENUE_LEAST to AVENUE_MOST wide.
const BLOCK_LEAST := 5.5
const BLOCK_MOST := 9.5
const SQUARE_LEAST := 8.0
const AVENUE_LEAST := 3.0
const AVENUE_MOST := 4.2
## Nothing is built within PAVEMENT m of the kerb.
const PAVEMENT := 0.35
## A lot is LOT_LEAST m across at least, and cut in two above LOT_MOST
## (if both halves are still lots).
const LOT_LEAST := 2.0
const LOT_MOST := 3.0
## How many shards a city is cut into, at most (as weight() tells it), and
## how many towers it has.
const MOST := 1900
const TOWERS_LEAST := 2
const TOWERS_MOST := 5
## Shards are about this big (m): finer for what is small. A thing cut
## with WHOLE is left in one piece (a car, a roof, the crown of a tree).
const FINE := 0.6
const COARSE := 0.75
const WHOLE := 4.0
## kg/m3 of what it is made of: little, a toy city is hollow.
const DENSITY := 300.0
## How fine the grid on the walls is (squares of 0.2 m: it reads as windows).
const SQUARES_PER_METRE := 1.25
## Cars are parked KERB m from the edge of an avenue, and drive LANE m from
## its middle.
const KERB := 0.45
const LANE := 0.5
## The railway: how high its deck stands (m), and about how long a span is.
const RAIL_HIGH := 0.62
const RAIL_SPAN := 2.85

const WALLS: Array[Color] = [
	Color(0.86, 0.8, 0.68),
	Color(0.8, 0.7, 0.6),
	Color(0.88, 0.84, 0.78),
	Color(0.76, 0.66, 0.58),
	Color(0.82, 0.78, 0.66),
]
const ROOFS: Array[Color] = [Color(0.55, 0.3, 0.24), Color(0.4, 0.36, 0.36), Color(0.5, 0.34, 0.26)]
const OFFICES: Array[Color] = [
	Color(0.62, 0.66, 0.72),
	Color(0.7, 0.7, 0.72),
	Color(0.58, 0.62, 0.66),
	Color(0.74, 0.72, 0.68),
]
const GLASS: Array[Color] = [Color(0.52, 0.64, 0.74), Color(0.6, 0.7, 0.76), Color(0.48, 0.58, 0.7)]
const CARS: Array[Color] = [
	Color(0.8, 0.2, 0.18),
	Color(0.9, 0.75, 0.2),
	Color(0.2, 0.4, 0.75),
	Color(0.9, 0.9, 0.9),
	Color(0.2, 0.2, 0.22),
	Color(0.25, 0.6, 0.35),
]
const TRUNK := Color(0.45, 0.32, 0.22)
const LEAVES := Color(0.3, 0.55, 0.28)
const CONCRETE := Color(0.6, 0.6, 0.6)
const TRAIN := Color(0.85, 0.5, 0.15)

## The number it was made up from.
var number := 0
## Its blocks on the ground (x and z), the square among them, and what each
## one is.
var blocks: Array[Rect2] = []
var kinds := PackedInt32Array()
var square := Rect2()
## Where things stand (the middle of their foot): towers, offices, houses,
## cars; and the two ends of the railway, if there is one.
var towers: Array[Vector3] = []
var offices: Array[Vector3] = []
var houses: Array[Vector3] = []
var cars: Array[Vector3] = []
var railway: Array[Vector3] = []
## Where the two brutes start, on the square.
var player_start := Vector3.ZERO
var brute_start := Vector3.ZERO

# The boxes it is made of, each [foot, size, turn, tint, grain].
var _boxes: Array[Array] = []
# Where the trees of the lot being planted stand.
var _trees: Array[Vector3] = []


func _init(of_number: int) -> void:
	number = of_number
	var fill := 1.0
	for attempt in 7:
		_plan(fill)
		if weight() <= MOST:
			break
		fill -= 0.12


## Adds the city to `s`, placed by `xf`.
func build(s: Structure, xf: Transform3D) -> void:
	for box in _boxes:
		var size: Vector3 = box[1]
		var foot: Vector3 = box[0]
		var placed := Transform3D(Basis(Vector3.UP, box[2]), foot + Vector3(0, size.y * 0.5, 0))
		s.add_box(xf * placed, size, box[3], box[4], _plain(size, box[4]))


## About how many shards it is cut into.
func weight() -> int:
	var shards := 0.0
	for box in _boxes:
		var size: Vector3 = box[1]
		var grain: float = box[4]
		var cells := 1.0
		for axis in 3:
			cells *= maxf(1.0, roundf(size[axis] / grain))
		shards += cells if _plain(size, grain) else cells * 1.4
	return roundi(shards)


## The pads the blocks stand on: where to lay a pavement (each one a middle
## and a size on the ground).
func pads() -> Array[Array]:
	var out: Array[Array] = []
	for block in blocks:
		var middle := block.get_center()
		out.append([Vector3(middle.x, 0, middle.y), block.size + Vector2.ONE * 0.5])
	return out


## A tour of the city for the showcase: where to stand and what to look
## at, fourteen stops at most. Every tower, then the offices and the houses
## nearest the square, each from the nearest kerb.
func tour() -> Array[Array]:
	var targets: Array[Vector3] = []
	for tower in towers:
		targets.append(tower + Vector3.UP * 1.0)
	for office in _nearest(offices, 6):
		targets.append(office + Vector3.UP * 0.8)
	for house in _nearest(houses, 14):
		targets.append(house + Vector3.UP * 0.4)
	var stops: Array[Array] = []
	for k in mini(targets.size(), 14):
		stops.append([_kerb(targets[k]), targets[k]])
	return stops


## The block that `at` is in (-1: in the street).
func block_at(at: Vector3) -> int:
	for k in blocks.size():
		if blocks[k].has_point(Vector2(at.x, at.z)):
			return k
	return -1


## The `count` nearest the square of `places`, nearest first.
func _nearest(places: Array[Vector3], count: int) -> Array[Vector3]:
	var sorted: Array[Vector3] = []
	sorted.assign(places)
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.length_squared() < b.length_squared())
	sorted.resize(mini(sorted.size(), count))
	return sorted


## In the street, 1.3 m off the nearest kerb of the block that `at` is in.
func _kerb(at: Vector3) -> Vector3:
	var block := blocks[maxi(block_at(at), 0)]
	var from := Vector3(at.x, 0, at.z)
	var west := at.x - block.position.x
	var east := block.end.x - at.x
	var north := at.z - block.position.y
	var south := block.end.y - at.z
	var least := minf(minf(west, east), minf(north, south))
	if least == west:
		from.x = block.position.x - 1.3
	elif least == east:
		from.x = block.end.x + 1.3
	elif least == north:
		from.z = block.position.y - 1.3
	else:
		from.z = block.end.y + 1.3
	return from


## Cut plain (see Structure.add_box): what is low, or cut coarse.
func _plain(size: Vector3, grain: float) -> bool:
	return grain >= 1.0 or size.y < 1.0


## Makes the city up, with `fill` of what it could hold (1: all of it).
func _plan(fill: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(number * 7919 + 13)
	_boxes.clear()
	blocks.clear()
	kinds.clear()
	towers.clear()
	offices.clear()
	houses.clear()
	cars.clear()
	railway.clear()
	var across := _streets(rng)
	var along := _streets(rng)
	var near: Array[int] = []
	for z in along.size():
		for x in across.size():
			var block := Rect2(across[x].x, along[z].x, across[x].y, along[z].y)
			if block.has_point(Vector2.ZERO):
				square = block
			blocks.append(block)
	# Districts: downtown more often next to the square, and twice at least.
	for k in blocks.size():
		var block := blocks[k]
		if block == square:
			kinds.append(SQUARE)
			continue
		var beside := block.grow(AVENUE_MOST + 0.1).intersects(square)
		var cornered := not _overlap(block, square, 0) and not _overlap(block, square, 1)
		var draw := rng.randf()
		var downtown := 0.22
		if beside and not cornered:
			near.append(k)
			downtown = 0.6
		kinds.append(DOWNTOWN if draw < downtown else PARK if draw > 0.9 else HOUSES)
	var downtowns := kinds.count(DOWNTOWN)
	for k in near:
		if downtowns < TOWERS_LEAST and kinds[k] != DOWNTOWN:
			kinds[k] = DOWNTOWN
			downtowns += 1
	for k in blocks.size():
		if kinds[k] != SQUARE:
			_district(blocks[k], kinds[k], rng, fill)
	_traffic(across, along, rng, fill)
	_plant_square(rng)
	var half := square.size.y * 0.5 - 1.3
	player_start = Vector3(0, 0.05, minf(3.2, half))
	brute_start = Vector3(1.5, 0.05, -minf(2.5, half))


## Where the blocks are along one way: for each, where it starts and how
## long it is. The one the square is in has the middle of the world for its
## middle.
func _streets(rng: RandomNumberGenerator) -> PackedVector2Array:
	var count := 3 if rng.randf() < 0.6 else 4
	var own := rng.randi_range(1, count - 2)
	var out := PackedVector2Array()
	var at := 0.0
	for k in count:
		var size := rng.randf_range(BLOCK_LEAST, BLOCK_MOST)
		if k == own:
			size = maxf(size, SQUARE_LEAST)
		out.append(Vector2(at, size))
		at += size + rng.randf_range(AVENUE_LEAST, AVENUE_MOST)
	var middle := out[own].x + out[own].y * 0.5
	for k in count:
		out[k].x -= middle
	return out


## Do `a` and `b` overlap along `axis` (0: x, 1: z)?
func _overlap(a: Rect2, b: Rect2, axis: int) -> bool:
	return a.position[axis] < b.end[axis] and b.position[axis] < a.end[axis]


## A block of `kind`: cut into lots, and each lot built on.
func _district(block: Rect2, kind: int, rng: RandomNumberGenerator, fill: float) -> void:
	var lots: Array[Rect2] = []
	_lots(block.grow(-PAVEMENT), rng, lots)
	for k in range(lots.size() - 1, 0, -1):
		var other := rng.randi_range(0, k)
		var kept := lots[k]
		lots[k] = lots[other]
		lots[other] = kept
	var tall := 0
	if kind == DOWNTOWN:
		tall = 2 if lots.size() >= 4 and rng.randf() < 0.35 * fill else 1
	for lot in lots:
		var draw := rng.randf()
		_trees.clear()
		if kind == DOWNTOWN:
			if tall > 0 and towers.size() < TOWERS_MOST:
				tall -= 1
				_tower(lot, rng)
			elif draw < 0.7 * fill:
				_office(lot, rng)
			elif draw < 0.85:
				_houses(lot, rng, fill)
			else:
				_park(lot, rng, 0.5)
		elif kind == HOUSES:
			if draw < 0.14 * fill:
				_office(lot, rng)
			elif draw < 0.22:
				_park(lot, rng, 0.8)
			else:
				_houses(lot, rng, fill)
		elif draw < 0.25:
			_houses(lot, rng, fill)
		else:
			_park(lot, rng, 1.0)


## Cuts `plot` into lots, added to `out`.
func _lots(plot: Rect2, rng: RandomNumberGenerator, out: Array[Rect2]) -> void:
	var axis := 0 if plot.size.x >= plot.size.y else 1
	var length := plot.size[axis]
	if length <= LOT_MOST or length < LOT_LEAST * 2.0:
		out.append(plot)
		return
	var cut := clampf(length * rng.randf_range(0.38, 0.62), LOT_LEAST, length - LOT_LEAST)
	var first := plot
	var second := plot
	first.size[axis] = cut
	second.position[axis] += cut
	second.size[axis] -= cut
	_lots(first, rng, out)
	_lots(second, rng, out)


## A tower: a tall body, a narrower top and a mast; or two bodies, one on
## the other. (Each body is slender: with half of a storey gone, what is
## above comes down, see Structure.SLENDER.)
func _tower(lot: Rect2, rng: RandomNumberGenerator) -> void:
	var tint := GLASS[rng.randi() % GLASS.size()]
	var wide := minf(rng.randf_range(1.7, 2.1), minf(lot.size.x, lot.size.y) - 0.3)
	var at := _within(lot, Vector2(wide, wide), rng)
	var top := 0.0
	towers.append(at)
	if rng.randf() < 0.4:
		wide = minf(wide, 1.75)
		var low := rng.randf_range(3.6, 4.0)
		var high := rng.randf_range(2.5, 2.9)
		_add(at, Vector3(wide, low, wide), 0.0, tint, COARSE)
		_add(at + Vector3(0, low, 0), Vector3(1.15, high, 1.15), 0.0, tint.lightened(0.12), COARSE)
		top = low + high
	else:
		var tall := rng.randf_range(4.4, 5.8)
		var cap := Vector3(wide * 0.63, 0.8, wide * 0.63)
		_add(at, Vector3(wide, tall, wide), 0.0, tint, COARSE)
		_add(at + Vector3(0, tall, 0), cap, 0.0, tint.darkened(0.15), FINE)
		top = tall + 0.8
	_add(at + Vector3(0, top, 0), Vector3(0.12, 0.9, 0.12), 0.0, CONCRETE.darkened(0.3), WHOLE)


## An office: as high as a brute or a little more, with a darker roof.
func _office(lot: Rect2, rng: RandomNumberGenerator) -> void:
	var tint := OFFICES[rng.randi() % OFFICES.size()]
	var most := 3.2 if minf(lot.size.x, lot.size.y) > 3.6 else 2.6
	var size := Vector3(
		minf(rng.randf_range(1.8, most), lot.size.x - 0.4),
		rng.randf_range(1.4, 2.6),
		minf(rng.randf_range(1.8, most), lot.size.y - 0.4)
	)
	var at := _within(lot, Vector2(size.x, size.z), rng)
	offices.append(at)
	_add(at, size, 0.0, tint, COARSE)
	var roof := Vector3(size.x * 0.6, 0.25, size.z * 0.6)
	_add(at + Vector3(0, size.y, 0), roof, 0.0, tint.darkened(0.25), WHOLE)


## Houses on a lot, side by side in one or two rows, each with its roof.
func _houses(lot: Rect2, rng: RandomNumberGenerator, fill: float) -> void:
	var turned := rng.randi_range(0, 1)
	var across := lot.size[turned]
	var deep := lot.size[1 - turned]
	var side := clampi(int((across - 0.1) / 1.45), 1, 3)
	var rows := clampi(int((deep - 0.1) / 1.75), 1, 2)
	var middle := lot.get_center()
	for row in rows:
		for k in side:
			if rng.randf() > fill + 0.1:
				continue
			# (As deep as its share of the lot lets it be, a gap left behind.)
			var size := Vector3(
				rng.randf_range(1.05, 1.3),
				rng.randf_range(0.6, 0.85),
				minf(rng.randf_range(1.3, 2.3), deep / rows - 0.3)
			)
			var off := Vector2(((k + 0.5) / side - 0.5) * across, ((row + 0.5) / rows - 0.5) * deep)
			if turned == 1:
				off = Vector2(off.y, off.x)
			var at := Vector3(middle.x + off.x, 0, middle.y + off.y)
			var turn := turned * PI * 0.5
			houses.append(at)
			_add(at, size, turn, WALLS[rng.randi() % WALLS.size()], FINE)
			var roof := Vector3(size.x + 0.1, 0.14, size.z + 0.1)
			_add(at + Vector3(0, size.y, 0), roof, turn, ROOFS[rng.randi() % ROOFS.size()], WHOLE)


## Trees on a lot: `share` of what it could hold.
func _park(lot: Rect2, rng: RandomNumberGenerator, share: float) -> void:
	var inside := lot.grow(-0.3)
	for k in clampi(roundi(lot.get_area() / 1.6 * share), 1, 8):
		var spot := inside.position + Vector2(rng.randf(), rng.randf()) * inside.size
		_tree(Vector3(spot.x, 0, spot.y), rng.randf_range(0.8, 1.2))


## A tree, unless there is one within reach of it already.
func _tree(at: Vector3, grown: float) -> void:
	for other in _trees:
		if other.distance_to(at) < 0.65:
			return
	_trees.append(at)
	_add(at, Vector3(0.09, 0.32, 0.09) * grown, 0.0, TRUNK, WHOLE)
	_add(at + Vector3(0, 0.32 * grown, 0), Vector3(0.42, 0.4, 0.42) * grown, 0.0, LEAVES, WHOLE)


## Cars on every avenue: parked along the kerbs, and a few on the road.
## And the railway, down the middle of one of them.
func _traffic(
	across: PackedVector2Array, along: PackedVector2Array, rng: RandomNumberGenerator, fill: float
) -> void:
	var busy := rng.randf_range(0.5, 1.0) * fill
	var railed := rng.randf() < 0.65
	var rail_way := rng.randi_range(0, 1)
	for way in 2:
		# Avenues that run along `way` (0: along z, between the blocks told by
		# `across`).
		var beside := across if way == 0 else along
		var crossed := along if way == 0 else across
		var from := crossed[0].x
		var to := crossed[crossed.size() - 1].x + crossed[crossed.size() - 1].y
		var rail := rng.randi_range(0, beside.size() - 2) if railed and way == rail_way else -1
		for k in beside.size() - 1:
			var left := beside[k].x + beside[k].y
			var right := beside[k + 1].x
			var middle := (left + right) * 0.5
			for lane: float in [left + KERB, middle - LANE, middle + LANE, right - KERB]:
				var parked := absf(lane - middle) > LANE + 0.01
				var at := from + rng.randf_range(0.4, 3.0)
				while at < to:
					if not _crossing(at, crossed):
						_car(_street(way, lane, at), way * PI * 0.5, CARS[rng.randi() % CARS.size()])
					at += (rng.randf_range(1.5, 4.5) if parked else rng.randf_range(4.0, 10.0)) / busy
			if k == rail:
				_railway(way, middle, from, to, rng)


## Is `at` along a street where it crosses another (between two of
## `crossed`)?
func _crossing(at: float, crossed: PackedVector2Array) -> bool:
	for k in crossed.size() - 1:
		if at > crossed[k].x + crossed[k].y - 0.25 and at < crossed[k + 1].x + 0.25:
			return true
	return false


## The place `at` m along the street that runs along `way` (0: along z),
## `lane` m across.
func _street(way: int, lane: float, at: float) -> Vector3:
	return Vector3(lane, 0, at) if way == 0 else Vector3(at, 0, lane)


func _car(at: Vector3, turn: float, tint: Color) -> void:
	cars.append(at)
	_add(at, Vector3(0.24, 0.13, 0.5), turn, tint, WHOLE)
	_add(at + Vector3(0, 0.13, 0), Vector3(0.21, 0.09, 0.26), turn, tint.lightened(0.25), WHOLE)


## A railway on stilts down the middle (`lane`) of the avenue that runs
## along `way`, from one end of the city to the other, and a train on it.
func _railway(way: int, lane: float, from: float, to: float, rng: RandomNumberGenerator) -> void:
	var spans := roundi((to - from) / RAIL_SPAN)
	var span := (to - from) / spans
	var turn := (1 - way) * PI * 0.5
	railway.append(_street(way, lane, from))
	railway.append(_street(way, lane, to))
	for k in spans + 1:
		var at := _street(way, lane, from + k * span)
		_add(at, Vector3(0.22, RAIL_HIGH, 0.22), 0.0, CONCRETE.darkened(0.1), WHOLE)
		if k < spans:
			var deck := _street(way, lane, from + (k + 0.5) * span) + Vector3.UP * RAIL_HIGH
			_add(deck, Vector3(span, 0.16, 0.7), turn, CONCRETE, 1.0)
	var coaches := rng.randi_range(3, 5)
	var head := rng.randf_range(from + 1.0, to - 1.0 - coaches)
	for k in coaches:
		var coach := _street(way, lane, head + k) + Vector3.UP * (RAIL_HIGH + 0.16)
		_add(coach, Vector3(0.92, 0.26, 0.34), turn, TRAIN, WHOLE)


## Trees round the square.
func _plant_square(rng: RandomNumberGenerator) -> void:
	_trees.clear()
	var inside := square.grow(-0.4)
	for way in 2:
		var at := inside.position[way] + rng.randf_range(0.2, 0.9)
		while at < inside.end[way]:
			for edge: float in [inside.position[1 - way], inside.end[1 - way]]:
				if rng.randf() < 0.8:
					_tree(_street(1 - way, edge, at), 1.0)
			at += rng.randf_range(1.5, 2.6)


## Somewhere in `lot` for something `foot` across to stand (the middle of
## its foot).
func _within(lot: Rect2, foot: Vector2, rng: RandomNumberGenerator) -> Vector3:
	var slack := (lot.size - foot) * 0.5 - Vector2.ONE * 0.1
	var off := Vector2(
		rng.randf_range(-1, 1) * maxf(slack.x, 0.0), rng.randf_range(-1, 1) * maxf(slack.y, 0.0)
	)
	var middle := lot.get_center()
	return Vector3(middle.x + off.x, 0, middle.y + off.y)


## A box standing at `at` (the middle of its foot), turned `turn` rad about
## the vertical, cut about `grain` m across.
func _add(at: Vector3, size: Vector3, turn: float, tint: Color, grain: float) -> void:
	_boxes.append([at, size, turn, tint, grain])
