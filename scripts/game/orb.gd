class_name Orb
extends Node3D
## A way to tidy up, not a power: while you hold the button, loose debris
## near you is drawn to a point in front of you and fuses there into one
## ball, which grows by what it swallows. Let go and the ball is put down,
## where it stays: one thing instead of hundreds of pieces. Hold again while
## looking at a ball and you take it back, to carry it elsewhere or to fill
## it further. Nothing is lost: the ball holds exactly the volume it
## swallowed.

enum State { HELD, DOWN }

const REACH := 11.0  ## m: loose pieces this near the ball are drawn in
const HOLD := 2.2  ## m in front of your eyes, plus the ball's own size
## It is held below where you look, by this much plus most of its size (m):
## what you look at stays in view above it.
const LOW := 0.25
const MOST := 8.0  ## m3 it can hold
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
const INFLOW := 1.4  ## m round the ball: where the streaks of air start from
const TAKE_BACK := 9.0  ## m: a ball you look at from nearer than this is taken back
const SHADER := preload("res://shaders/orb.gdshader")

var structure: Structure
var eye: Node3D  ## it is held in front of this
var state := State.HELD
var volume := 0.0  ## m3 swallowed so far
var centre := Vector3.ZERO

var _grip: Array[Vector3i] = []  # (piece, its serial, steps so far) on their way in
var _refused := {}  # Vector2i(piece, serial): given up on
var _steps := 0
var _pulse := 0.0  # it swells a little as it swallows
var _glow := 1.0  # it glows while it is held
var _turn := Basis()
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _inflow: CPUParticles3D
var _body: RID
var _shape: RID


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
	_inflow = Fx.make_inflow(int(Quality.pick(14, 20, 28)), CORE + INFLOW)
	add_child(_inflow)
	centre = _hold_point()
	_show()


func _exit_tree() -> void:
	_free_body()


func _physics_process(delta: float) -> void:
	_steps += 1
	if state == State.HELD:
		centre = centre.lerp(_hold_point(), 1.0 - exp(-14.0 * delta))
		_draw_in()


func _process(delta: float) -> void:
	_pulse = move_toward(_pulse, 0.0, delta * 4.0)
	_glow = move_toward(_glow, 1.0 if state == State.HELD else 0.0, delta * 3.0)
	if state == State.HELD:
		_turn = _turn.rotated(Vector3.UP, delta * 0.9)
	_show()


## How big the ball is (m).
func radius() -> float:
	return maxf(CORE, pow(volume * 0.75 / PI, 1.0 / 3.0))


## How full it is, 0 to 1.
func fill() -> float:
	return clampf(volume / MOST, 0.0, 1.0)


## You let go: the ball is put down where it is held, and stays there.
## (With nothing in it, it just goes out.)
func put_down() -> void:
	if state != State.HELD:
		return
	var p := structure.pieces
	for g in _grip:
		if p.alive[g.x] == 1 and p.serial_of(g.x) == g.y:
			p.let_go(g.x)
	_grip.clear()
	_inflow.emitting = false
	if volume <= 0.0:
		queue_free()
		return
	state = State.DOWN
	# A heavy ball like any loose piece, that does not roll far.
	_shape = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(_shape, radius())
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(_body, _shape)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_MASS, volume * Structure.DENSITY)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.0)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 3.0)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.3)
	PhysicsServer3D.body_set_collision_layer(_body, Structure.LAYER_DEBRIS)
	PhysicsServer3D.body_set_collision_mask(_body, Pieces.MASK)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(_turn, centre))
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_set_state_sync_callback(_body, _moved)


## You take a ball that was put down back in hand, as it is.
func take_back() -> void:
	if state != State.DOWN:
		return
	_free_body()
	# What was lying on it falls.
	var around := Vector3.ONE * (radius() + 0.3)
	structure.pieces.thaw_box(centre - around, centre + around + Vector3.UP * 0.6)
	state = State.HELD
	_refused.clear()
	_inflow.emitting = true


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
			volume += p.mass[i] / Structure.DENSITY
			p.take(i)
			_pulse = 1.0
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


## Called by the physics engine while it lies there (and rolls a little).
func _moved(state_now: PhysicsDirectBodyState3D) -> void:
	centre = state_now.transform.origin
	_turn = state_now.transform.basis


func _free_body() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		PhysicsServer3D.free_rid(_shape)
		_body = RID()


func _show() -> void:
	_mesh.global_transform = Transform3D(_turn.scaled(Vector3.ONE * radius() * (1.0 + 0.1 * _pulse)), centre)
	_mat.set_shader_parameter("power", _glow + _pulse * 0.8)
	_inflow.global_position = centre
	# (From just around the ball: nearer the eye a streak would fill the view.)
	var reach := radius() + INFLOW
	_inflow.emission_sphere_radius = reach
	_inflow.radial_accel_min = -2.0 * reach / (_inflow.lifetime * _inflow.lifetime)
	_inflow.radial_accel_max = _inflow.radial_accel_min
