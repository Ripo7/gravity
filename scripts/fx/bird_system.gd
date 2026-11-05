class_name BirdSystem
extends Node3D
## Life in the city: pigeons perched in small groups on roof edges and
## gulls circling high above. Anything violent nearby scares the pigeons
## off with a clap of wings; they circle for a while, then come back to a
## roof that is still standing.
##
## No physics and no nodes per bird: positions are integrated here and the
## whole flock is one MultiMesh (shaders/bird.gdshader flaps the wings).

enum State { PERCHED, FLEEING, CIRCLING, RETURNING }

const PERCH_CELL := 2.0  ## metres; one perch per cell, the highest block top
const PERCH_MIN_Y := 3.0
const FLEE_SPEED := 9.0
const FLY_SPEED := 6.5
const FLEE_TIME := 2.2
const PIGEON := Color(0.36, 0.37, 0.42)
const PIGEON_LIGHT := Color(0.55, 0.55, 0.6)
const GULL := Color(0.93, 0.93, 0.9)
const FLOATS := 20  # transform 12 + colour 4 + custom 4

var structures: StructureSet
var count := 0
var _pigeons := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _state := PackedByteArray()
var _timer := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _perch := PackedVector3Array()
var _perch_block := PackedInt32Array()  ## structure block under the perch
var _orbit := PackedVector3Array()  ## circle centre while circling
var _angle := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _color: Array[Color] = []
var _perches: Array[Dictionary] = []  ## {at, block}
var _buffer := PackedFloat32Array()
var _multimesh: MultiMesh
var _last_flap := -10.0


func setup(structure_set: StructureSet) -> void:
	structures = structure_set
	_find_perches()
	var groups := int(Quality.pick(5, 8, 10))
	var gulls := int(Quality.pick(5, 8, 10))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var homes: Array[Dictionary] = []
	for g in mini(groups, _perches.size()):
		homes.append(_perches[rng.randi_range(0, _perches.size() - 1)])
	for home in homes:
		for k in rng.randi_range(3, 6):
			var off := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			_add_bird(home["at"] + off, home["block"], State.PERCHED, rng)
	_pigeons = count
	for k in gulls:
		var c := Vector3(rng.randf_range(-25, 25), rng.randf_range(26, 36), rng.randf_range(-25, 25))
		var i := _add_bird(c, -1, State.CIRCLING, rng)
		_orbit[i] = c
		_radius[i] = rng.randf_range(10.0, 18.0)
		_color[i] = GULL
	_build_mesh()


func _add_bird(at: Vector3, block: int, state: int, rng: RandomNumberGenerator) -> int:
	var i := count
	count += 1
	_pos.append(at)
	_vel.append(Vector3.ZERO)
	_state.append(state)
	_timer.append(rng.randf_range(0.0, 4.0))
	_yaw.append(rng.randf_range(0.0, TAU))
	_perch.append(at)
	_perch_block.append(block)
	_orbit.append(at)
	_angle.append(rng.randf_range(0.0, TAU))
	_radius.append(8.0)
	_phase.append(rng.randf_range(0.0, TAU))
	_color.append(PIGEON.lerp(PIGEON_LIGHT, rng.randf()))
	return i


## The highest block top in each 2 m cell, if it is high enough to be a
## roof or a ledge (and not glass).
func _find_perches() -> void:
	_perches.clear()
	if structures == null:
		return
	var best := {}
	for i in structures.segment_count():
		if not structures.is_alive(i) or structures.kind_of(i) == Materials.Kind.GLASS:
			continue
		var xf := structures.transform_of(i)
		var top := xf.origin + xf.basis.y.normalized() * structures.size_of(i).y * 0.5
		if top.y < PERCH_MIN_Y:
			continue
		var key := Vector2i(floori(top.x / PERCH_CELL), floori(top.z / PERCH_CELL))
		if not best.has(key) or (best[key]["at"] as Vector3).y < top.y:
			best[key] = {"at": top, "block": i}
	for v: Dictionary in best.values():
		_perches.append(v)


## Pigeons within `radius` of `at` take off.
func scare(at: Vector3, radius: float) -> void:
	var scared := 0
	var centre := Vector3.ZERO
	for i in _pigeons:
		if _state[i] == State.FLEEING:
			continue
		if _state[i] == State.CIRCLING:
			continue
		if _pos[i].distance_to(at) > radius:
			continue
		_take_off(i, at)
		scared += 1
		centre += _pos[i]
	if scared >= 2:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_flap > 0.6:
			_last_flap = now
			Sfx.play("birds_flap", centre / scared, -3.0 + minf(scared, 12) * 0.4)


func _take_off(i: int, from: Vector3) -> void:
	var away := _pos[i] - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	away = away.normalized().rotated(Vector3.UP, randf_range(-0.5, 0.5))
	_vel[i] = away * FLEE_SPEED * 0.6 + Vector3.UP * 4.0
	_state[i] = State.FLEEING
	_timer[i] = FLEE_TIME * randf_range(0.8, 1.3)


func _process(delta: float) -> void:
	if count == 0:
		return
	for i in count:
		match _state[i]:
			State.PERCHED:
				_perched(i, delta)
			State.FLEEING:
				_fleeing(i, delta)
			State.CIRCLING:
				_circling(i, delta)
			State.RETURNING:
				_returning(i, delta)
		_write(i)
	_multimesh.buffer = _buffer


func _perched(i: int, delta: float) -> void:
	# The roof went: fly.
	var b := _perch_block[i]
	if b >= 0 and structures != null and not structures.is_alive(b):
		_take_off(i, _pos[i] + Vector3(randf() - 0.5, -1.0, randf() - 0.5))
		return
	# Now and then a little turn on the spot.
	_timer[i] -= delta
	if _timer[i] <= 0.0:
		_timer[i] = randf_range(1.5, 6.0)
		_yaw[i] += randf_range(-1.2, 1.2)


func _fleeing(i: int, delta: float) -> void:
	var v := _vel[i]
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() > 0.1:
		flat = flat.normalized()
	v = v.move_toward(flat * FLEE_SPEED + Vector3.UP * 3.5, 14.0 * delta)
	_vel[i] = v
	_pos[i] += v * delta
	_timer[i] -= delta
	if _timer[i] <= 0.0:
		_state[i] = State.CIRCLING
		_timer[i] = randf_range(8.0, 14.0)
		_radius[i] = randf_range(6.0, 11.0)
		_orbit[i] = _pos[i] + Vector3(0, randf_range(3.0, 7.0), 0) - flat * _radius[i]
		_angle[i] = atan2(_pos[i].z - _orbit[i].z, _pos[i].x - _orbit[i].x)


func _circling(i: int, delta: float) -> void:
	var r := _radius[i]
	_angle[i] += FLY_SPEED / r * delta * (1.0 if i % 2 == 0 else -1.0)
	var target := _orbit[i] + Vector3(cos(_angle[i]) * r, sin(_angle[i] * 0.7 + i) * 0.8, sin(_angle[i]) * r)
	var v := (target - _pos[i]) / maxf(delta, 0.001)
	_vel[i] = _vel[i].lerp(v.limit_length(FLY_SPEED * 1.6), clampf(4.0 * delta, 0.0, 1.0))
	_pos[i] += _vel[i] * delta
	if i >= _pigeons:
		return  # gulls circle for ever
	_timer[i] -= delta
	if _timer[i] <= 0.0:
		_pick_perch(i)
		_state[i] = State.RETURNING


func _returning(i: int, delta: float) -> void:
	var to := _perch[i] - _pos[i]
	var d := to.length()
	if d < 0.25:
		_pos[i] = _perch[i]
		_vel[i] = Vector3.ZERO
		_state[i] = State.PERCHED
		_timer[i] = randf_range(1.0, 4.0)
		return
	var speed := minf(FLY_SPEED, 1.0 + d * 1.2)
	_vel[i] = _vel[i].move_toward(to / d * speed, 10.0 * delta)
	_pos[i] += _vel[i] * delta


## Back home if the roof still stands, else the nearest perch that does.
func _pick_perch(i: int) -> void:
	var b := _perch_block[i]
	if b >= 0 and structures.is_alive(b):
		return
	var best := -1
	var best_d := INF
	for k in _perches.size():
		var pb: int = _perches[k]["block"]
		if not structures.is_alive(pb):
			continue
		var d := (_perches[k]["at"] as Vector3).distance_squared_to(_pos[i])
		if d < best_d:
			best_d = d
			best = k
	if best < 0:
		_state[i] = State.CIRCLING
		_timer[i] = 30.0
		return
	var off := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	_perch[i] = (_perches[best]["at"] as Vector3) + off
	_perch_block[i] = _perches[best]["block"]


func _write(i: int) -> void:
	var basis: Basis
	var flap_rate := 0.0
	var flap_amount := 0.0
	var span := 0.22  # folded wings
	var v := _vel[i]
	if _state[i] == State.PERCHED:
		basis = Basis(Vector3.UP, _yaw[i])
	else:
		var fwd := v.normalized() if v.length() > 0.1 else Vector3.FORWARD
		basis = Basis.looking_at(fwd, Vector3.UP)
		# Bank into turns a little.
		basis = basis * Basis(Vector3.FORWARD, clampf(-v.cross(Vector3.UP).dot(fwd) * 0.05, -0.5, 0.5))
		span = 1.0
		var climbing := v.y > 0.5 or _state[i] == State.FLEEING
		# Glide in long arcs, flap hard when climbing or fleeing.
		var glide := 0.5 + 0.5 * sin(_angle[i] * 2.0 + float(i))
		flap_rate = 22.0 if climbing else 14.0
		flap_amount = 0.9 if climbing else (0.12 if glide > 0.6 else 0.6)
	if i >= _pigeons:
		basis = basis.scaled(Vector3.ONE * 2.2)
	else:
		basis = basis.scaled(Vector3.ONE * 1.3)
	var o := i * FLOATS
	_buffer[o + 0] = basis.x.x
	_buffer[o + 1] = basis.y.x
	_buffer[o + 2] = basis.z.x
	_buffer[o + 3] = _pos[i].x
	_buffer[o + 4] = basis.x.y
	_buffer[o + 5] = basis.y.y
	_buffer[o + 6] = basis.z.y
	_buffer[o + 7] = _pos[i].y
	_buffer[o + 8] = basis.x.z
	_buffer[o + 9] = basis.y.z
	_buffer[o + 10] = basis.z.z
	_buffer[o + 11] = _pos[i].z
	var c := _color[i]
	_buffer[o + 12] = c.r
	_buffer[o + 13] = c.g
	_buffer[o + 14] = c.b
	_buffer[o + 15] = 1.0
	_buffer[o + 16] = _phase[i]
	_buffer[o + 17] = flap_rate
	_buffer[o + 18] = flap_amount
	_buffer[o + 19] = span


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body: a little double pyramid, nose forward (-z). UV.x = 0: rigid.
	var nose := Vector3(0, 0.01, -0.16)
	var tail := Vector3(0, 0.0, 0.17)
	var l := Vector3(-0.045, 0, 0)
	var r := Vector3(0.045, 0, 0)
	var top := Vector3(0, 0.05, -0.02)
	var bottom := Vector3(0, -0.04, 0)
	for tri in [
		[nose, top, l],
		[nose, r, top],
		[tail, l, top],
		[tail, top, r],
		[nose, l, bottom],
		[nose, bottom, r],
		[tail, bottom, l],
		[tail, r, bottom],
	]:
		for p: Vector3 in tri:
			st.set_uv(Vector2(0, 0))
			st.add_vertex(p)
	# Wings: UV.x = -1 (left) / +1 (right) so the shader flaps them.
	for side in [-1.0, 1.0]:
		var root_front := Vector3(0.03 * side, 0.02, -0.06)
		var root_back := Vector3(0.03 * side, 0.02, 0.07)
		var tip := Vector3(0.33 * side, 0.02, 0.04)
		for p: Vector3 in [root_front, tip, root_back]:
			st.set_uv(Vector2(side, 0))
			st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = mesh
	_multimesh.instance_count = count
	_buffer.resize(count * FLOATS)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bird.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Birds"
	mmi.multimesh = _multimesh
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 120, 300))
	add_child(mmi)
	for i in count:
		_write(i)
	_multimesh.buffer = _buffer
