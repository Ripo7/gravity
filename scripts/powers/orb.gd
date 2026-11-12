class_name Orb
extends Node3D
## Orb: while you hold it, loose debris near you is drawn to a point in
## front of you and fuses there into one ball, which grows by what it
## swallows. Let go and the ball is thrown where you look: it knocks out
## what it hits and bursts back into the shards it was made of. Nothing is
## lost on the way: the ball holds exactly the volume it swallowed.

## It hit something (or gave up) at `at`, holding `volume` m3.
signal burst(at: Vector3, volume: float)

enum State { GATHER, FLY, SPILL }

const REACH := 11.0  ## m: loose pieces this near the ball are drawn in
const HOLD := 2.2  ## m in front of your eyes, plus the ball's own size
## It is held below where you look, by this much plus most of its size (m):
## what you aim at stays in view above it.
const LOW := 0.25
const MOST := 5.0  ## m3 it can hold
const GRIP := 14  ## pieces on their way in at once
const NEW_PER_LOOK := 3  ## pieces taken hold of per look around
const LOOK_EVERY := 3  ## steps between two looks around
const SIGHT_TRIES := 10  ## pieces checked for a clear way in per look
const PULL := 9.5  ## m/s, the speed pieces come in at (heavy ones slower)
## Pieces do not come straight in: they rise (m per m still to go, up to
## RISE_MOST) and wind round the ball (m/s), so you see them coming.
const RISE := 0.3
const RISE_MOST := 1.4
const SWIRL := 3.0
const DWINDLE := 1.6  ## m from the ball: from there a piece shrinks into it
const GIVE_UP := 150  ## steps: a piece that has not made it by then is let go
const CORE := 0.3  ## m: the size it shows before it has swallowed anything
const THROW := 26.0  ## m/s
const FALL := 0.5  ## how much of gravity it feels in flight
## m3 of standing wall knocked out per m3 of ball, thrown at THROW.
const POWER := 1.3
const SPILL_PER_STEP := 30  ## shards given back per step when it bursts
const LIFE := 6.0  ## s in flight before it bursts by itself
const AIR := Color(0.85, 0.92, 1.0)
const SHADER := preload("res://shaders/orb.gdshader")

var structure: Structure
var eye: Node3D  ## it is held in front of this, and thrown where it looks
var state := State.GATHER
var volume := 0.0  ## m3 swallowed so far
var centre := Vector3.ZERO
var velocity := Vector3.ZERO

var _held := PackedInt32Array()  # the shards it is made of
var _grip: Array[Vector3i] = []  # (piece, its serial, steps so far) on their way in
var _refused := {}  # Vector2i(piece, serial): given up on
var _steps := 0
var _pulse := 0.0  # it swells a little as it swallows
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _inflow: CPUParticles3D
var _body: RID
var _shape: RID
var _hit := false
var _hit_at := Vector3.ZERO
var _was := Vector3.ZERO  # its velocity before it hit
var _age := 0.0
var _burst_radius := 0.0


func setup(s: Structure, from: Node3D) -> void:
	structure = s
	eye = from


func _ready() -> void:
	add_to_group("orb")
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 18
	ball.rings = 10
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mesh = MeshInstance3D.new()
	_mesh.mesh = ball
	_mesh.material_override = _mat
	add_child(_mesh)
	_inflow = Fx.make_inflow(int(Quality.pick(14, 20, 28)), 3.2)
	add_child(_inflow)
	centre = _hold_point()
	_show()


func _exit_tree() -> void:
	_free_body()


func _physics_process(delta: float) -> void:
	_steps += 1
	match state:
		State.GATHER:
			centre = centre.lerp(_hold_point(), 1.0 - exp(-14.0 * delta))
			_draw_in()
		State.FLY:
			_age += delta
			if _hit or _age > LIFE or centre.y < -5.0:
				_burst()
		State.SPILL:
			_spill()


func _process(delta: float) -> void:
	_pulse = move_toward(_pulse, 0.0, delta * 4.0)
	_mesh.rotate_y(delta * (0.9 if state == State.GATHER else 5.0))
	_show()


## How big the ball is (m).
func radius() -> float:
	return maxf(CORE, pow(volume * 0.75 / PI, 1.0 / 3.0))


## How full it is, 0 to 1.
func fill() -> float:
	return clampf(volume / MOST, 0.0, 1.0)


## You let go: the ball is thrown where you look. (With nothing in it, it
## just goes out.)
func throw() -> void:
	if state != State.GATHER:
		return
	var p := structure.pieces
	for g in _grip:
		if p.alive[g.x] == 1 and p.serial_of(g.x) == g.y:
			p.let_go(g.x)
	_grip.clear()
	if _held.is_empty():
		queue_free()
		return
	_inflow.emitting = false
	velocity = _aim()
	_was = velocity
	state = State.FLY
	# Nothing sees it (no layer): it only stops at the ground and at what
	# still stands, and goes through loose pieces.
	_shape = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(_shape, radius())
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(_body, _shape)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_MASS, volume * Structure.DENSITY)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, FALL)
	PhysicsServer3D.body_set_collision_layer(_body, 0)
	PhysicsServer3D.body_set_collision_mask(_body, Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(_body, true)
	PhysicsServer3D.body_set_max_contacts_reported(_body, 4)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), centre))
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_set_state_sync_callback(_body, _flew)


## Where it is held: in front of the eye and a little below, never in a
## wall or in the ground.
func _hold_point() -> Vector3:
	var from := eye.global_position
	var dir := -eye.global_basis.z
	var r := radius()
	var out := HOLD + r * 1.6
	var ray := PhysicsRayQueryParameters3D.create(
		from, from + dir * (out + r), Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		out = clampf(from.distance_to(hit["position"]) - r - 0.05, 0.6, out)
	var at := from + dir * out - eye.global_basis.y * (LOW + r * 0.9)
	at.y = maxf(at.y, r + 0.05)
	return at


## The velocity that takes it from where it is held to what you look at.
func _aim() -> Vector3:
	var from := eye.global_position
	var dir := -eye.global_basis.z
	var target := from + dir * 40.0
	var ray := PhysicsRayQueryParameters3D.create(
		from, target, Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		target = hit["position"]
	var to := target - centre
	var time := to.length() / THROW
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	# (Thrown a little high, by what it will fall on the way.)
	return to / time + Vector3.UP * 0.5 * gravity * FALL * time


## Pieces on their way come nearer and are swallowed when they arrive; now
## and then it looks around for more.
func _draw_in() -> void:
	var p := structure.pieces
	var near := radius() * 0.7 + 0.15
	var coming := 0.0
	for k in range(_grip.size() - 1, -1, -1):
		var g := _grip[k]
		var i := g.x
		if p.alive[i] == 0 or p.serial_of(i) != g.y:
			_grip.remove_at(k)  # it broke up on the way: its parts are loose again
			continue
		var to := centre - p.transform_of(i).origin
		var d := to.length()
		if d < near:
			_grip.remove_at(k)
			_swallow(i)
			continue
		if g.z > GIVE_UP:
			_grip.remove_at(k)
			_refused[Vector2i(i, g.y)] = true
			p.let_go(i)
			continue
		_grip[k] = Vector3i(i, g.y, g.z + 1)
		coming += p.mass[i] / Structure.DENSITY
		var speed := PULL / (1.0 + p.mass[i] / 4000.0)
		var size := 0.2 + 0.8 * clampf((d - near) / DWINDLE, 0.0, 1.0)
		var way := (to + Vector3.UP * minf(d * RISE, RISE_MOST)).normalized() * speed
		way += Vector3.UP.cross(to / d) * SWIRL * clampf(d / 4.0, 0.0, 1.0)
		p.drag(i, p.velocity_of(i).lerp(way, 0.3), size)
	if _steps % LOOK_EVERY == 0 and _grip.size() < GRIP and volume + coming < MOST:
		_look_around(coming)


## Takes hold of the nearest loose pieces it can see that still fit in.
func _look_around(coming: float) -> void:
	var p := structure.pieces
	var found: Array[Vector2] = []  # (distance, piece)
	for i in p.top:
		if p.alive[i] == 0 or p.gripped[i] == 1:
			continue
		var d := p.transform_of(i).origin.distance_squared_to(centre)
		if d < REACH * REACH and not _refused.has(Vector2i(i, p.serial_of(i))):
			found.append(Vector2(d, i))
	found.sort()
	var space := get_world_3d().direct_space_state
	var taken := 0
	var tries := 0
	for f in found:
		if taken >= NEW_PER_LOOK or tries >= SIGHT_TRIES or _grip.size() >= GRIP:
			break
		var i := int(f.y)
		var size := p.mass[i] / Structure.DENSITY
		if volume + coming + size > MOST:
			continue
		tries += 1
		# Not what is behind a wall: it would only press against it.
		var ray := PhysicsRayQueryParameters3D.create(
			centre, p.transform_of(i).origin, Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
		)
		if not space.intersect_ray(ray).is_empty():
			continue
		p.grip(i)
		_grip.append(Vector3i(i, p.serial_of(i), 0))
		coming += size
		taken += 1


func _swallow(i: int) -> void:
	var p := structure.pieces
	volume += p.mass[i] / Structure.DENSITY
	_held.append_array(p.take(i))
	_pulse = 1.0


## Called by the physics engine while it flies.
func _flew(state: PhysicsDirectBodyState3D) -> void:
	centre = state.transform.origin
	velocity = state.linear_velocity
	if _hit:
		return
	if state.get_contact_count() > 0:
		_hit = true
		_hit_at = state.get_contact_local_position(0)
	else:
		_was = velocity


## It knocks out what it hit, then gives back what it is made of.
func _burst() -> void:
	var at := _hit_at if _hit else centre
	_burst_radius = radius()
	_free_body()
	if _hit:
		var hard := clampf(_was.length_squared() / (THROW * THROW), 0.15, 1.3)
		structure.crush(at, volume * POWER * hard, _was * 0.5, maxf(1.6, _burst_radius + 1.0))
	state = State.SPILL
	_mesh.visible = false
	var ring := BlastWave.spawn(
		get_parent(), Transform3D(Basis(), centre), _burst_radius, _burst_radius * 3.0 + 1.5, 0.35, AIR
	)
	(ring.material_override as ShaderMaterial).set_shader_parameter("glow", 1.4)
	var cam := get_viewport().get_camera_3d() as CameraShake
	if cam:
		var far := cam.global_position.distance_to(centre)
		cam.add_trauma(clampf(0.5 * fill() + 0.15, 0.0, 0.6) / (1.0 + far * 0.08))
	structure.released.emit(centre, volume, _was)
	burst.emit(at, volume)


## The shards it holds come back as loose pieces, thrown on and apart.
func _spill() -> void:
	var p := structure.pieces
	for n in mini(SPILL_PER_STEP, _held.size()):
		var m := _held[_held.size() - 1]
		_held.remove_at(_held.size() - 1)
		var out := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		var at := centre + out * _burst_radius * 0.75 * pow(randf(), 0.33)
		var turned := Basis(Vector3(randf() - 0.5, randf() - 0.5, randf() + 0.01).normalized(), randf() * TAU)
		var v := _was * randf_range(0.15, 0.5) + out * randf_range(1.5, 6.0) + Vector3.UP * 1.5
		var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 8.0
		volume -= structure.volume[m]
		p.give(m, Transform3D(turned, at), v, spin, true)
	if _held.is_empty():
		queue_free()


func _free_body() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		PhysicsServer3D.free_rid(_shape)
		_body = RID()


func _show() -> void:
	_mesh.global_position = centre
	_inflow.global_position = centre
	_mesh.scale = Vector3.ONE * radius() * (1.0 + 0.1 * _pulse)
	_mat.set_shader_parameter("power", (1.0 if state == State.GATHER else 0.6) + _pulse * 0.8)
