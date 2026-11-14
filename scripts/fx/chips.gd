class_name Chips
extends MultiMeshInstance3D
## Small bits thrown out where something breaks: they fly, bounce once,
## and stay where they land. They are decoration (no physics bodies): one
## ray each per step while they fly, nothing once they rest. When all are in
## use, the oldest is taken again.

const GRAVITY := 9.8
const MASK := (
	Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS | Structure.LAYER_LITTER
)
const COLORS: Array[Color] = [Color(0.6, 0.6, 0.63), Color(0.42, 0.42, 0.45), Color(0.32, 0.32, 0.35)]

var capacity := 0
## How many may fly at once (more are simply not thrown).
var flying_limit := 0

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _turn := PackedFloat32Array()  # angle now
var _rate := PackedFloat32Array()  # rad/s
var _size := PackedVector3Array()  # half extents: each bit is squashed its own way
var _bounced := PackedByteArray()
var _flying := PackedInt32Array()
var _perched := PackedInt32Array()  # resting on something other than the ground
var _next := 0
var _used := 0
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
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _bit()
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	for i in capacity:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		mm.set_instance_color(i, COLORS[0])
	multimesh = mm
	custom_aabb = AABB(Vector3.ONE * -200.0, Vector3.ONE * 400.0)
	_ray.collision_mask = MASK


## Throws `count` bits from around `at`, with `velocity` plus their own
## scatter.
func burst(at: Vector3, count: int, velocity: Vector3, scatter := 3.0) -> void:
	for k in mini(count, flying_limit - _flying.size()):
		var i := _next
		_next = (_next + 1) % capacity
		if _used < capacity:
			_used += 1
			multimesh.visible_instance_count = _used
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
		_size[i] = (
			Vector3(_rng.randf_range(0.5, 1.0), _rng.randf_range(0.3, 0.7), _rng.randf_range(0.5, 1.0))
			* _rng.randf_range(0.04, 0.1)
		)
		_bounced[i] = 0
		_flying.append(i)
		multimesh.set_instance_color(i, COLORS[_rng.randi() % COLORS.size()])
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
		var v := _vel[i]
		v.y -= GRAVITY * delta
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
			_pos[i] = (hit["position"] as Vector3) + n * _size[i].y * 0.7
			if _bounced[i] == 0 and v.length() > 2.5:
				_bounced[i] = 1
				_vel[i] = v.bounce(n) * 0.3
				_rate[i] *= 0.5
			elif n.y < 0.5 and v.length() > 0.5:
				# Against a wall: it slides down.
				_vel[i] = v.slide(n) * 0.5
			else:
				_flying.remove_at(k)
				if _pos[i].y > 0.2:
					_perched.append(i)
		_show(i)


func _show(i: int) -> void:
	multimesh.set_instance_transform(
		i, Transform3D(Basis(_axis[i], _turn[i]) * Basis.from_scale(_size[i]), _pos[i])
	)


## A rough little lump: a sphere of a few faces, squashed differently for
## each bit. (A mesh built by hand, one shard cut by Fracture, came out as
## garbage in the browser when drawn through a MultiMesh, though fine on
## desktop; the engine's own shapes do not.)
func _bit() -> Mesh:
	var lump := SphereMesh.new()
	lump.radius = 1.0
	lump.height = 2.0
	lump.radial_segments = 5
	lump.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic_specular = 0.1
	lump.material = mat
	return lump
