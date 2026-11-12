class_name House
extends RefCounted
## A small greybox house to take apart: two floors, a door and windows, a
## row of pillars inside under each slab, and a balcony over a porch held by
## four pillars. Given as
## boxes (two opposite corners each); Structure cuts them into shards.
## The front looks toward +Z.

const WALL := Color(0.62, 0.62, 0.65)
const SLAB := Color(0.5, 0.5, 0.54)
const PILLAR := Color(0.72, 0.6, 0.48)
const T := 0.35  ## wall thickness
const X0 := -4.5
const X1 := 4.5
const Z0 := -3.5
const Z1 := 3.5
const PORCH := 3.4  ## how far the balcony sticks out in front
const FLOOR := 3.0  ## top of the ground-floor walls
const UP := 3.3  ## foot of the upper walls (the slab is 0.3 thick)
const TOP := 6.0  ## top of the upper walls


## Adds the house to `s`, placed by `xf`.
static func build(s: Structure, xf: Transform3D) -> void:
	var walls: Array[Array] = []
	var slabs: Array[Array] = []
	var pillars: Array[Array] = []
	# Ground floor.
	walls.append([Vector3(X0, 0, Z0), Vector3(X1, FLOOR, Z0 + T)])  # back
	_side(walls, X0, 0.0, FLOOR, 1.0, 2.2)
	_side(walls, X1 - T, 0.0, FLOOR, 1.0, 2.2)
	walls.append([Vector3(X0, 0, Z1 - T), Vector3(-0.7, FLOOR, Z1)])  # front, left of the door
	walls.append([Vector3(-0.7, 2.2, Z1 - T), Vector3(0.7, FLOOR, Z1)])  # over the door
	walls.append([Vector3(0.7, 0, Z1 - T), Vector3(2.0, FLOOR, Z1)])
	walls.append([Vector3(2.0, 0, Z1 - T), Vector3(3.4, 1.0, Z1)])  # under the window
	walls.append([Vector3(2.0, 2.2, Z1 - T), Vector3(3.4, FLOOR, Z1)])  # over it
	walls.append([Vector3(3.4, 0, Z1 - T), Vector3(X1, FLOOR, Z1)])
	_row(pillars, 0.0, FLOOR)
	# The floor above, sticking out over the porch, and the porch's pillars.
	slabs.append([Vector3(X0, FLOOR, Z0), Vector3(X1, UP, Z1 + PORCH)])
	for x: float in [X0, -1.725, 1.275, X1 - 0.45]:
		pillars.append([Vector3(x, 0, Z1 + PORCH - 0.45), Vector3(x + 0.45, FLOOR, Z1 + PORCH)])
	# Upper floor.
	walls.append([Vector3(X0, UP, Z0), Vector3(X1, TOP, Z0 + T)])
	_side(walls, X0, UP, TOP, 4.2, 5.3)
	_side(walls, X1 - T, UP, TOP, 4.2, 5.3)
	walls.append([Vector3(X0, UP, Z1 - T), Vector3(-3.0, TOP, Z1)])
	walls.append([Vector3(-3.0, UP, Z1 - T), Vector3(-1.6, 4.2, Z1)])
	walls.append([Vector3(-3.0, 5.3, Z1 - T), Vector3(-1.6, TOP, Z1)])
	walls.append([Vector3(-1.6, UP, Z1 - T), Vector3(-0.6, TOP, Z1)])
	walls.append([Vector3(-0.6, 5.5, Z1 - T), Vector3(0.6, TOP, Z1)])  # over the balcony door
	walls.append([Vector3(0.6, UP, Z1 - T), Vector3(1.6, TOP, Z1)])
	walls.append([Vector3(1.6, UP, Z1 - T), Vector3(3.0, 4.2, Z1)])
	walls.append([Vector3(1.6, 5.3, Z1 - T), Vector3(3.0, TOP, Z1)])
	walls.append([Vector3(3.0, UP, Z1 - T), Vector3(X1, TOP, Z1)])
	_row(pillars, UP, TOP)
	# The balcony's low wall.
	walls.append([Vector3(X0, UP, Z1 + PORCH - 0.2), Vector3(X1, 4.2, Z1 + PORCH)])
	walls.append([Vector3(X0, UP, Z1), Vector3(X0 + 0.2, 4.2, Z1 + PORCH - 0.2)])
	walls.append([Vector3(X1 - 0.2, UP, Z1), Vector3(X1, 4.2, Z1 + PORCH - 0.2)])
	# Roof.
	slabs.append([Vector3(X0 - 0.3, TOP, Z0 - 0.3), Vector3(X1 + 0.3, TOP + 0.3, Z1 + 0.3)])
	for kind: Array in [[walls, WALL], [slabs, SLAB], [pillars, PILLAR]]:
		for box: Array in kind[0]:
			var a: Vector3 = box[0]
			var b: Vector3 = box[1]
			s.add_box(xf * Transform3D(Basis(), (a + b) * 0.5), (b - a).abs(), kind[1])


## A side wall at `x` from `y0` to `y1`, with a window from `sill` to `head`.
static func _side(walls: Array[Array], x: float, y0: float, y1: float, sill: float, head: float) -> void:
	walls.append([Vector3(x, y0, Z0 + T), Vector3(x + T, y1, -0.9)])
	walls.append([Vector3(x, y0, 0.9), Vector3(x + T, y1, Z1 - T)])
	walls.append([Vector3(x, y0, -0.9), Vector3(x + T, sill, 0.9)])
	walls.append([Vector3(x, head, -0.9), Vector3(x + T, y1, 0.9)])


## Three pillars across the middle of the house, from `y0` to `y1`: they
## halve the span of the slab above.
static func _row(pillars: Array[Array], y0: float, y1: float) -> void:
	for x: float in [-2.5, 0.0, 2.5]:
		pillars.append([Vector3(x - 0.25, y0, -0.25), Vector3(x + 0.25, y1, 0.25)])
