class_name Chips
extends Node3D
## Small bits thrown out where something breaks: they fly, bounce once,
## and stay where they land. They are decoration (no physics bodies): one
## ray each per step while they fly, nothing once they rest. What breaks
## says what flies: bricks, lumps of concrete, shards of glass, bits of
## roof tile, leaves, splinters. Each kind is a little model made in
## Blender (tools/blender/rubble.py) and one draw call, with room for its
## share of the bits; when all of a kind are in use, the oldest is taken
## again.

enum Kind { LUMP, BRICK, GLASS, TILE, LEAF, SPLINTER }

const GRAVITY := 9.8
const MASK := (
	Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS | Structure.LAYER_LITTER
)
const MODELS_FILE := "res://assets/fx/rubble.json"
const MODELS: Array[String] = ["lump", "brick", "glass", "tile", "leaf", "splinter"]
## Of all the bits there is room for, the share of each kind.
const SHARE: Array[float] = [0.34, 0.26, 0.24, 0.06, 0.06, 0.04]
## How big a bit of each kind is, from and to (m, about half its length).
const SIZE: Array[Vector2] = [
	Vector2(0.05, 0.11),
	Vector2(0.07, 0.11),
	Vector2(0.05, 0.14),
	Vector2(0.06, 0.09),
	Vector2(0.05, 0.08),
	Vector2(0.08, 0.16),
]
## How hard each kind falls (leaves float down), and whether it lies flat
## where it lands.
const WEIGHT: Array[float] = [1.0, 1.0, 1.0, 1.0, 0.22, 0.8]
const FLAT: Array[bool] = [false, false, true, true, true, false]
## What colour a bit is when it is not told one.
const COLORS: Array[Array] = [
	[Color(0.62, 0.62, 0.65), Color(0.46, 0.46, 0.49), Color(0.36, 0.36, 0.39)],
	[Color(0.82, 0.38, 0.25), Color(0.7, 0.3, 0.2), Color(0.88, 0.5, 0.33)],
	[Color(0.75, 0.9, 1.0), Color(0.6, 0.8, 0.95), Color(0.9, 0.97, 1.0)],
	[Color(0.85, 0.42, 0.24), Color(0.72, 0.34, 0.2)],
	[Color(0.3, 0.6, 0.28), Color(0.4, 0.68, 0.3)],
	[Color(0.5, 0.33, 0.18), Color(0.62, 0.45, 0.26)],
]

var capacity := 0
## How many may fly at once (more are simply not thrown).
var flying_limit := 0

var _meshes: Array[MultiMesh] = []
var _first := PackedInt32Array()  # per kind: its first bit, how many it has room for,
var _room := PackedInt32Array()
var _next := PackedInt32Array()  # which one it takes next, how many are in use
var _used := PackedInt32Array()
var _kind := PackedByteArray()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _turn := PackedFloat32Array()  # angle now
var _rate := PackedFloat32Array()  # rad/s
var _size := PackedVector3Array()  # half extents: each bit is squashed its own way
var _bounced := PackedByteArray()
var _flying := PackedInt32Array()
var _perched := PackedInt32Array()  # resting on something other than the ground
var _ray := PhysicsRayQueryParameters3D.new()
# Their own dice: effects must not change how the building breaks in a
# repeatable run.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	capacity = int(Quality.pick(500, 900, 1400))
	flying_limit = int(Quality.pick(50, 100, 160))
	_pos.resize(capacity)
	_vel.resize(capacity)
	_axis.resize(capacity)
	_turn.resize(capacity)
	_rate.resize(capacity)
	_size.resize(capacity)
	_bounced.resize(capacity)
	_kind.resize(capacity)
	var models: Dictionary = (load(MODELS_FILE) as JSON).data
	var from := 0
	for kind in MODELS.size():
		var room := int(capacity * SHARE[kind]) if kind > 0 else 0
		_first.append(from)
		_room.append(room)
		_next.append(0)
		_used.append(0)
		from += room
	# (The lumps take what is left over.)
	_room[0] = capacity - from
	for kind in range(1, MODELS.size()):
		_first[kind] += _room[0]
	for kind in MODELS.size():
		for i in range(_first[kind], _first[kind] + _room[kind]):
			_kind[i] = kind
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _bit(models[MODELS[kind]], kind)
		mm.instance_count = _room[kind]
		mm.visible_instance_count = 0
		for i in _room[kind]:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			mm.set_instance_color(i, Color.WHITE)
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = mm
		drawn.custom_aabb = AABB(Vector3.ONE * -200.0, Vector3.ONE * 400.0)
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drawn)
		_meshes.append(mm)
	_ray.collision_mask = MASK


## Throws `count` bits of `kind` from around `at`, with `velocity` plus
## their own scatter; in `tint` if it is given (else in the colours of
## their kind).
func burst(
	at: Vector3, count: int, velocity: Vector3, scatter := 3.0, kind := Kind.LUMP, tint := Color(0, 0, 0, 0)
) -> void:
	for k in mini(count, flying_limit - _flying.size()):
		var i := _first[kind] + _next[kind]
		_next[kind] = (_next[kind] + 1) % _room[kind]
		if _used[kind] < _room[kind]:
			_used[kind] += 1
			_meshes[kind].visible_instance_count = _used[kind]
		else:
			# Taken back from wherever it was.
			var f := _flying.find(i)
			if f >= 0:
				_flying.remove_at(f)
			var p := _perched.find(i)
			if p >= 0:
				_perched.remove_at(p)
		_pos[i] = at + Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * 0.4
		_vel[i] = (
			velocity + Vector3(_rng.randf() - 0.5, _rng.randf() * 0.8, _rng.randf() - 0.5) * 2.0 * scatter
		)
		_axis[i] = Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized()
		_turn[i] = _rng.randf() * TAU
		_rate[i] = _rng.randf_range(4.0, 14.0)
		var squash := Vector3(
			_rng.randf_range(0.75, 1.0), _rng.randf_range(0.6, 1.0), _rng.randf_range(0.75, 1.0)
		)
		_size[i] = squash * _rng.randf_range(SIZE[kind].x, SIZE[kind].y)
		_bounced[i] = 0
		_flying.append(i)
		var colours: Array = COLORS[kind]
		var colour: Color = colours[_rng.randi() % colours.size()]
		if tint.a > 0.0:
			colour = tint * _rng.randf_range(0.8, 1.1)
		_meshes[kind].set_instance_color(i - _first[kind], colour)
		_show(i)


## What bits rested on near `at` moved away: they fall again.
func disturb(at: Vector3, reach: float) -> void:
	for k in range(_perched.size() - 1, -1, -1):
		var i := _perched[k]
		var off := _pos[i] - at
		if Vector2(off.x, off.z).length() < reach and absf(off.y) < reach + 1.0:
			_perched.remove_at(k)
			if _flying.size() < flying_limit * 2:
				_vel[i] = Vector3.ZERO
				_bounced[i] = 1
				_flying.append(i)


func _physics_process(delta: float) -> void:
	if _flying.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for k in range(_flying.size() - 1, -1, -1):
		var i := _flying[k]
		var kind := _kind[i]
		var v := _vel[i]
		v.y -= GRAVITY * WEIGHT[kind] * delta
		if WEIGHT[kind] < 0.5:
			# (What floats down is held back by the air.)
			v -= v * minf(2.5 * delta, 1.0)
		var from := _pos[i]
		var to := from + v * delta
		_ray.from = from
		_ray.to = to
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			_pos[i] = to
			_vel[i] = v
			_turn[i] += _rate[i] * delta
		else:
			var n: Vector3 = hit["normal"]
			_pos[i] = (hit["position"] as Vector3) + n * _size[i].y * (0.15 if FLAT[kind] else 0.7)
			if _bounced[i] == 0 and v.length() > 2.5:
				_bounced[i] = 1
				_vel[i] = v.bounce(n) * 0.3
				_rate[i] *= 0.5
			elif n.y < 0.5 and v.length() > 0.5:
				# Against a wall: it slides down.
				_vel[i] = v.slide(n) * 0.5
			else:
				_flying.remove_at(k)
				if FLAT[kind]:
					# It lies flat on what it landed on.
					var tip := Vector3.UP.cross(n)
					_axis[i] = tip.normalized() if tip.length() > 0.01 else Vector3.UP
					_turn[i] = Vector3.UP.angle_to(n)
				if _pos[i].y > 0.2:
					_perched.append(i)
		_show(i)


func _show(i: int) -> void:
	var kind := _kind[i]
	_meshes[kind].set_instance_transform(
		i - _first[kind], Transform3D(Basis(_axis[i], _turn[i]) * Basis.from_scale(_size[i]), _pos[i])
	)


## The model of a kind of bit, from what Blender made (per corner of each
## triangle: where it is, which way it faces, how light it is there).
func _bit(model: Dictionary, kind: int) -> Mesh:
	var places: Array = model["v"]
	var facings: Array = model["n"]
	var tones: Array = model["c"]
	var lightest: float = tones.max()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for k in tones.size():
		verts.append(Vector3(places[3 * k], places[3 * k + 1], places[3 * k + 2]))
		normals.append(Vector3(facings[3 * k], facings[3 * k + 1], facings[3 * k + 2]))
		var tone: float = tones[k] / lightest
		colors.append(Color(tone, tone, tone))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic_specular = 0.1
	if kind == Kind.GLASS:
		# Glass catches the light as it turns.
		mat.roughness = 0.15
		mat.metallic = 0.3
		mat.metallic_specular = 0.9
	if kind == Kind.LEAF:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	made.surface_set_material(0, mat)
	return made
