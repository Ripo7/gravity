class_name RubbleField
extends Node3D
## The rubble left where things broke: heaps of crushed stone, brick and
## plaster on the ground, as much of it as broke away. The debris pool and
## the gravel chips only keep so much; whatever they let go of lands here
## instead of vanishing (a falling tower leaves a mound, not a few stones).
##
## A grid of heights over the square, a point a metre. Each lot is added
## where it lands and slides down until no slope is steeper than rubble
## stands (about 35 degrees, a little more or less from point to point, so
## heaps are not cones). Drawn by one MultiMesh of 8 m tiles (only the tiles
## with rubble) whose vertex shader reads the heights from a texture; the
## pieces, the gravel and the player stand on a height map per tile.

const HALF := 52.0  ## m: the field covers the square (Arena.inner)
const CELL := 1.0  ## m between two points
const TILE := 8  ## cells along a tile's side
## Steepest step between two neighbouring points (m): rubble stands at about
## 35 degrees.
const REPOSE := 0.7
## Rubble takes more room than the stone it was (the gaps between stones).
const BULK := 1.3
## Below this (m) a point has no rubble: the surface hides under the floor.
const THIN := 0.004
const EMPTY := -0.3
const UPLOAD := 0.1  ## seconds between two uploads of the texture
## Seconds between two rebuilds of a tile's collision, and how much (m) a
## point must have risen or sunk to rebuild it: a height map that changes
## under resting pieces keeps them awake.
const COLLIDE := 2.0
const COLLIDE_STEP := 0.2
## Points the rubble may slide from per frame, by tier: a big lot flows out
## over a few frames, like a heap settling.
const FLOW_STEPS := Vector3i(300, 600, 900)
const SHADER := preload("res://shaders/rubble.gdshader")

## Loose volume on the ground (m^3, BULK times the solid volume it was).
var volume := 0.0

var _n := 0  ## points along a side
var _tiles := 0  ## tiles along a side
var _h := PackedFloat32Array()  ## height of rubble per point (m)
var _col := PackedByteArray()  ## its colour, RGBA8 (sRGB)
var _slope := PackedFloat32Array()  ## steepest step each point holds (m)
var _queue := PackedInt32Array()  ## points that may have to slide
var _head := 0
var _queued := PackedByteArray()
var _dirty := false
var _dirty_tiles := {}
var _built := {}  ## tile -> the heights its collision was built with
var _collide_tick := 0.0
var _shown := PackedInt32Array()  ## tile -> MultiMesh slot, -1 while it has no rubble
var _shown_count := 0
var _bodies := {}  ## tile -> [body RID, shape RID]
var _img_h: Image
var _img_c: Image
var _tex_h: ImageTexture
var _tex_c: ImageTexture
var _mm: MultiMesh
var _tick := 0.0
var _steps := 600


func _ready() -> void:
	_steps = int(Quality.pick(FLOW_STEPS.x, FLOW_STEPS.y, FLOW_STEPS.z))
	_tiles = ceili(HALF * 2.0 / (CELL * TILE))
	_n = _tiles * TILE + 1
	_h.resize(_n * _n)
	_h.fill(0.0)
	_col.resize(_n * _n * 4)
	_col.fill(0)
	_queued.resize(_n * _n)
	_queued.fill(0)
	_slope.resize(_n * _n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	for k in _n * _n:
		_slope[k] = REPOSE * rng.randf_range(0.8, 1.2)
	_shown.resize(_tiles * _tiles)
	_shown.fill(-1)
	_img_h = Image.create_from_data(_n, _n, false, Image.FORMAT_RF, _h.to_byte_array())
	_img_c = Image.create_from_data(_n, _n, false, Image.FORMAT_RGBA8, _col)
	_tex_h = ImageTexture.create_from_image(_img_h)
	_tex_c = ImageTexture.create_from_image(_img_c)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("heights", _tex_h)
	mat.set_shader_parameter("colors", _tex_c)
	mat.set_shader_parameter("field", Vector4(-_span(), -_span(), CELL, float(_n)))
	mat.set_shader_parameter("empty", EMPTY)
	mat.set_shader_parameter("thin", THIN)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _tile_mesh()
	_mm.instance_count = _tiles * _tiles
	_mm.visible_instance_count = 0
	# Bounds over the whole field: no walk over the tiles when one is added.
	_mm.custom_aabb = AABB(Vector3(-_span(), -1, -_span()), Vector3(_span() * 2.0, 30, _span() * 2.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RubbleMesh"
	mmi.multimesh = _mm
	mmi.material_override = mat
	add_child(mmi)


func _exit_tree() -> void:
	for pair: Array in _bodies.values():
		PhysicsServer3D.free_rid(pair[0])
		PhysicsServer3D.free_rid(pair[1])
	_bodies.clear()


## Adds `solid` m^3 of broken material, of colour `color`, where `at` is
## (straight down: the field is the rubble on the ground). A small lot is
## shared out between the four points round it, a big one is laid as a low
## cone; either way it then slides down to a stable slope.
func deposit(at: Vector3, solid: float, color: Color) -> void:
	if solid <= 0.0 or _n == 0:
		return
	var loose := solid * BULK
	volume += loose
	var gx := clampf((at.x + _span()) / CELL, 0.0, _n - 1.001)
	var gz := clampf((at.z + _span()) / CELL, 0.0, _n - 1.001)
	var area := CELL * CELL
	# Radius (in cells) of a cone of that volume at the angle of repose.
	var r := pow(3.0 * loose / (PI * REPOSE / CELL), 1.0 / 3.0) / CELL
	if r <= 1.2:
		var x0 := floori(gx)
		var z0 := floori(gz)
		var fx := gx - x0
		var fz := gz - z0
		_add(x0, z0, loose / area * (1.0 - fx) * (1.0 - fz), color)
		_add(x0 + 1, z0, loose / area * fx * (1.0 - fz), color)
		_add(x0, z0 + 1, loose / area * (1.0 - fx) * fz, color)
		_add(x0 + 1, z0 + 1, loose / area * fx * fz, color)
		return
	var ri := ceili(r)
	var cx := roundi(gx)
	var cz := roundi(gz)
	var weights := PackedFloat32Array()
	var total := 0.0
	for z in range(cz - ri, cz + ri + 1):
		for x in range(cx - ri, cx + ri + 1):
			var w := maxf(r - Vector2(x - gx, z - gz).length(), 0.0)
			weights.append(w)
			total += w
	if total <= 0.0:
		_add(cx, cz, loose / area, color)
		return
	var k := 0
	for z in range(cz - ri, cz + ri + 1):
		for x in range(cx - ri, cx + ri + 1):
			if weights[k] > 0.0:
				_add(x, z, loose / area * weights[k] / total, color)
			k += 1


## Height of the rubble's surface at `at` (x, z), 0 where there is none.
func height_at(at: Vector3) -> float:
	if _n == 0:
		return 0.0
	var gx := clampf((at.x + _span()) / CELL, 0.0, _n - 1.001)
	var gz := clampf((at.z + _span()) / CELL, 0.0, _n - 1.001)
	var x0 := floori(gx)
	var z0 := floori(gz)
	var fx := gx - x0
	var fz := gz - z0
	var k := z0 * _n + x0
	var a := lerpf(_h[k], _h[k + 1], fx)
	var b := lerpf(_h[k + _n], _h[k + _n + 1], fx)
	return lerpf(a, b, fz)


## Colour of rubble made of `kind` with finish seed `seed_value`.
static func color_of(kind: int, seed_value: float) -> Color:
	return GrainCloud.color_of(kind, seed_value)


func _span() -> float:
	return (_n - 1) * CELL * 0.5


## `vol` m^3 (loose) more at point (x, z), mixing its colour in.
func _add(x: int, z: int, vol: float, color: Color) -> void:
	if vol <= 0.0 or x < 0 or z < 0 or x >= _n or z >= _n:
		return
	var k := z * _n + x
	var dh := vol / (CELL * CELL)
	var before := _h[k]
	_h[k] = before + dh
	var o := k * 4
	if before < THIN:
		_col[o] = int(color.r * 255.0)
		_col[o + 1] = int(color.g * 255.0)
		_col[o + 2] = int(color.b * 255.0)
		_col[o + 3] = 255
	else:
		var t := dh / (before + dh)
		_col[o] = int(lerpf(_col[o], color.r * 255.0, t))
		_col[o + 1] = int(lerpf(_col[o + 1], color.g * 255.0, t))
		_col[o + 2] = int(lerpf(_col[o + 2], color.b * 255.0, t))
	_touch(x, z)
	_enqueue(k)


## Moves `m` m of height from point `a` to point `b` (colour goes with it).
func _move(a: int, b: int, m: float) -> void:
	var before := _h[b]
	_h[a] -= m
	_h[b] = before + m
	var oa := a * 4
	var ob := b * 4
	if before < THIN:
		_col[ob] = _col[oa]
		_col[ob + 1] = _col[oa + 1]
		_col[ob + 2] = _col[oa + 2]
		_col[ob + 3] = 255
	else:
		var t := m / (before + m)
		_col[ob] = int(lerpf(_col[ob], _col[oa], t))
		_col[ob + 1] = int(lerpf(_col[ob + 1], _col[oa + 1], t))
		_col[ob + 2] = int(lerpf(_col[ob + 2], _col[oa + 2], t))
	_touch(a % _n, a / _n)
	_touch(b % _n, b / _n)


func _enqueue(k: int) -> void:
	if _queued[k] == 0:
		_queued[k] = 1
		_queue.append(k)


## Marks the tiles point (x, z) belongs to (two or four on a tile's edge).
func _touch(x: int, z: int) -> void:
	_dirty = true
	var tx := mini(x / TILE, _tiles - 1)
	var tz := mini(z / TILE, _tiles - 1)
	_dirty_tiles[tz * _tiles + tx] = true
	var ex := x % TILE == 0 and x > 0
	var ez := z % TILE == 0 and z > 0
	if ex:
		_dirty_tiles[tz * _tiles + tx - 1] = true
	if ez:
		_dirty_tiles[(tz - 1) * _tiles + tx] = true
	if ex and ez:
		_dirty_tiles[(tz - 1) * _tiles + tx - 1] = true


func _process(delta: float) -> void:
	_flow(_steps)
	_tick += delta
	_collide_tick += delta
	if _dirty and _tick >= UPLOAD:
		_tick = 0.0
		_upload()


## The rubble slides: each point steeper than its slope allows towards a
## neighbour gives that neighbour half the excess (the steepest way down
## first), then both are looked at again, and so is what stands above the
## point that sank.
func _flow(steps: int) -> void:
	var diag := sqrt(2.0)
	while steps > 0 and _head < _queue.size():
		steps -= 1
		var k := _queue[_head]
		_head += 1
		_queued[k] = 0
		var h := _h[k]
		if h < THIN:
			continue
		var x := k % _n
		var z := k / _n
		var best := -1
		var most := 0.0
		for dz in range(-1, 2):
			var nz := z + dz
			if nz < 0 or nz >= _n:
				continue
			for dx in range(-1, 2):
				var nx := x + dx
				if (dx == 0 and dz == 0) or nx < 0 or nx >= _n:
					continue
				var q := nz * _n + nx
				var limit := _slope[k] * (diag if dx != 0 and dz != 0 else 1.0)
				var excess := h - _h[q] - limit
				if excess > most:
					most = excess
					best = q
		if best >= 0 and most > 0.002:
			_move(k, best, minf(most * 0.5, h))
			_enqueue(k)
			_enqueue(best)
			# It sank: what is above it round it may slide down to it now.
			var now := _h[k]
			for dz in range(-1, 2):
				var nz := z + dz
				if nz < 0 or nz >= _n:
					continue
				for dx in range(-1, 2):
					var nx := x + dx
					if nx >= 0 and nx < _n and _h[nz * _n + nx] > now + REPOSE * 0.5:
						_enqueue(nz * _n + nx)
	if _head >= _queue.size():
		_queue.clear()
		_head = 0
	elif _head > 4096:
		_queue = _queue.slice(_head)
		_head = 0


## Sends the heights and colours to the GPU, shows the tiles that now have
## rubble and rebuilds the height maps of the tiles that changed.
func _upload() -> void:
	_dirty = false
	_img_h.set_data(_n, _n, false, Image.FORMAT_RF, _h.to_byte_array())
	_tex_h.update(_img_h)
	_img_c.set_data(_n, _n, false, Image.FORMAT_RGBA8, _col)
	_tex_c.update(_img_c)
	var collide := _collide_tick >= COLLIDE
	if collide:
		_collide_tick = 0.0
	var later := {}
	for t: int in _dirty_tiles:
		if not _rebuild_tile(t, collide):
			later[t] = true
	_dirty_tiles = later
	_dirty = not later.is_empty()


## Shows tile `t` once it has rubble and, with `collide`, rebuilds its
## collision if its heights moved enough (or it had none). False when the
## collision still has to follow.
func _rebuild_tile(t: int, collide: bool) -> bool:
	var tx := t % _tiles
	var tz := t / _tiles
	var side := TILE + 1
	var hs := PackedFloat32Array()
	hs.resize(side * side)
	var top := EMPTY
	for j in side:
		var row := (tz * TILE + j) * _n + tx * TILE
		for i in side:
			var h := _h[row + i]
			var v := h if h >= THIN else EMPTY
			hs[j * side + i] = v
			top = maxf(top, v)
	if top <= EMPTY:
		return true
	if _shown[t] < 0:
		_shown[t] = _shown_count
		var origin := Vector3(tx * TILE * CELL - _span(), 0.0, tz * TILE * CELL - _span())
		_mm.set_instance_transform(_shown_count, Transform3D(Basis(), origin))
		_shown_count += 1
		_mm.visible_instance_count = _shown_count
	if not _bodies.has(t) and not collide:
		return false
	if _bodies.has(t):
		if not collide:
			return false
		var before: PackedFloat32Array = _built[t]
		var moved := 0.0
		for k in hs.size():
			moved = maxf(moved, absf(hs[k] - before[k]))
		if moved < COLLIDE_STEP:
			return false
	_built[t] = hs
	var data := {"width": side, "depth": side, "heights": hs, "min_height": EMPTY, "max_height": top}
	if not _bodies.has(t):
		var shape := PhysicsServer3D.heightmap_shape_create()
		PhysicsServer3D.shape_set_data(shape, data)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_collision_layer(body, DebrisSystem.LAYER_RUBBLE)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		var half := TILE * CELL * 0.5
		var centre := Vector3(tx * TILE * CELL - _span() + half, 0.0, tz * TILE * CELL - _span() + half)
		PhysicsServer3D.body_set_state(
			body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), centre)
		)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
		PhysicsServer3D.body_set_space(body, get_world_3d().space)
		_bodies[t] = [body, shape]
	else:
		PhysicsServer3D.shape_set_data(_bodies[t][1], data)
	return true


## One tile: a grid of TILE x TILE cells from its corner (the shader lifts
## each vertex to the rubble there).
func _tile_mesh() -> ArrayMesh:
	var side := TILE + 1
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for j in side:
		for i in side:
			verts.append(Vector3(i * CELL, 0.0, j * CELL))
	for j in TILE:
		for i in TILE:
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			# Clockwise seen from above (Godot's front faces).
			index.append_array(PackedInt32Array([a, b, d, a, d, c]))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(0, -1, 0), Vector3(TILE * CELL, 30, TILE * CELL))
	return mesh
