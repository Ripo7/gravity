class_name StreetDecor
extends Node3D
## Fills the district's streets once the buildings are in: lamps and fire
## braziers along the facades, pipe runs against the walls, war standards
## and guardian statues in the open squares. Placed from a distance field
## of the free ground (so nothing blocks a door or a street), drawn as one
## MultiMesh per kind, each with a simple box collider. They do not break.

const HALF := 50.0  ## half size of the area searched, metres
const CELL := 1.0
## kind: [min distance to a facade, max distance, spacing, collider size]
const KINDS := {
	"lamppost": [1.0, 2.2, 13.0, Vector3(0.7, 6.0, 0.7)],
	"brazier": [1.4, 2.6, 17.0, Vector3(1.1, 2.0, 1.1)],
	"pipes": [0.6, 1.1, 15.0, Vector3(8.0, 1.8, 0.6)],
	"standard": [5.0, 9.0, 20.0, Vector3(1.0, 9.0, 1.0)],
	"plinth_statue": [7.0, 99.0, 26.0, Vector3(1.6, 6.0, 1.6)],
}

var _n := 0
var _dist := PackedFloat32Array()  ## metres to the nearest building, per cell
var _placed := {}  ## kind -> Array[Transform3D]
var _taken: Array[Vector3] = []
var _flames: Array[Vector3] = []


## Lays the decor out around `structures`, keeping clear of `keep_clear`
## (the player start).
func setup(structures: StructureSet, keep_clear: Vector3) -> void:
	var kit := Megacity.kit()
	if kit.is_empty():
		return
	_distance_field(structures)
	_taken.append(keep_clear)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for kind: String in ["plinth_statue", "standard", "brazier", "lamppost", "pipes"]:
		_scatter(kind, rng)
	for kind: String in _placed:
		if kit.has(kind):
			add_child(Megacity.batch(kit[kind], _placed[kind], kind, true))
	for at in _flames:
		add_child(_flame(at))


func _distance_field(structures: StructureSet) -> void:
	_n = int(HALF * 2.0 / CELL)
	_dist.resize(_n * _n)
	_dist.fill(INF)
	var queue: Array[Vector2i] = []
	for i in structures.segment_count():
		var xf := structures.transform_of(i)
		var size := structures.size_of(i)
		if xf.origin.y - size.y * 0.5 > 2.5:
			continue  # walkways and upper floors leave the ground free
		var box := xf * AABB(-size * 0.5, size)
		var lo := _cell(box.position)
		var hi := _cell(box.end)
		for x in range(maxi(lo.x, 0), mini(hi.x, _n - 1) + 1):
			for z in range(maxi(lo.y, 0), mini(hi.y, _n - 1) + 1):
				if _dist[x * _n + z] > 0.0:
					_dist[x * _n + z] = 0.0
					queue.append(Vector2i(x, z))
	# Walls of the arena count as buildings too.
	for k in _n:
		for c: Vector2i in [Vector2i(k, 0), Vector2i(k, _n - 1), Vector2i(0, k), Vector2i(_n - 1, k)]:
			if _dist[c.x * _n + c.y] > 0.0:
				_dist[c.x * _n + c.y] = 0.0
				queue.append(c)
	# Breadth-first, 8 neighbours: a good enough distance in metres.
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d := _dist[c.x * _n + c.y]
		for o: Vector2i in [
			Vector2i(1, 0),
			Vector2i(-1, 0),
			Vector2i(0, 1),
			Vector2i(0, -1),
			Vector2i(1, 1),
			Vector2i(1, -1),
			Vector2i(-1, 1),
			Vector2i(-1, -1),
		]:
			var nb := c + o
			if nb.x < 0 or nb.y < 0 or nb.x >= _n or nb.y >= _n:
				continue
			var step := CELL * (1.4142 if o.x != 0 and o.y != 0 else 1.0)
			if _dist[nb.x * _n + nb.y] > d + step:
				_dist[nb.x * _n + nb.y] = d + step
				queue.append(nb)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x + HALF) / CELL), floori((p.z + HALF) / CELL))


func _world(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL - HALF, 0, (c.y + 0.5) * CELL - HALF)


func _scatter(kind: String, rng: RandomNumberGenerator) -> void:
	var spec: Array = KINDS[kind]
	var lo: float = spec[0]
	var hi: float = spec[1]
	var spacing: float = spec[2]
	var cells: Array[Vector2i] = []
	for x in _n:
		for z in _n:
			var d := _dist[x * _n + z]
			if d >= lo and d <= hi:
				cells.append(Vector2i(x, z))
	# Shuffle, then keep every spot far enough from what is already there.
	for k in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t := cells[k]
		cells[k] = cells[j]
		cells[j] = t
	var mine: Array[Vector3] = []
	for c in cells:
		var at := _world(c)
		var ok := true
		for q in mine:
			if q.distance_to(at) < spacing:
				ok = false
				break
		if ok:
			for q in _taken:
				if q.distance_to(at) < 3.0:
					ok = false
					break
		if not ok:
			continue
		mine.append(at)
		_taken.append(at)
		_place(kind, at, c, spec[3])


func _place(kind: String, at: Vector3, c: Vector2i, collider: Vector3) -> void:
	# Face away from the nearest wall (pipes run along it).
	var grad := Vector2(
		_d(c + Vector2i(1, 0)) - _d(c - Vector2i(1, 0)), _d(c + Vector2i(0, 1)) - _d(c - Vector2i(0, 1))
	)
	var yaw := atan2(grad.x, grad.y) if grad.length() > 0.01 else 0.0
	var basis := Basis(Vector3.UP, yaw)
	if kind == "pipes":
		# Hug the wall: back off toward it.
		at -= Vector3(grad.x, 0, grad.y).normalized() * 0.4
	if not _placed.has(kind):
		_placed[kind] = []
	(_placed[kind] as Array).append(Transform3D(basis, at))
	if kind == "brazier":
		_flames.append(at + Vector3(0, 2.0, 0))
	var body := StaticBody3D.new()
	body.collision_layer = DebrisSystem.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collider
	shape.shape = box
	shape.position = Vector3(0, collider.y * 0.5, 0)
	body.add_child(shape)
	body.transform = Transform3D(basis, at)
	add_child(body)


func _d(c: Vector2i) -> float:
	if c.x < 0 or c.y < 0 or c.x >= _n or c.y >= _n:
		return 0.0
	return minf(_dist[c.x * _n + c.y], 20.0)


## A small fire: a few warm additive billboards rising from the bowl.
func _flame(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = 6
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.8, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.1
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.75, 0.35, 0.9))
	grad.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 1.2)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Megacity.soft_dot()
	quad.material = m
	p.mesh = quad
	return p
