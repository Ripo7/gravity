class_name Orb
extends Node3D
## A ball of magic held in front of you while you hold the button: it draws
## in the loose debris around it, which dwindles into it and is gone. Let go
## and it closes. It breaks nothing that stands: only what has already come
## off the building goes in (a loose block too big to come comes apart).
## What it swallows is gone for good (its volume is still counted, see
## Pieces.taken_volume).

const REACH := 11.0  ## m: loose pieces this near the orb are drawn in
const HOLD := 2.4  ## m in front of your eyes
const LOW := 0.55  ## m below where you look: what you look at stays in view
const SIZE := 0.42  ## m: its radius
const GRIP := 16  ## pieces on their way in at once
const NEW_PER_LOOK := 3  ## pieces taken hold of per look around
const LOOK_EVERY := 3  ## steps between two looks around
const SIGHT_TRIES := 10  ## pieces checked for a clear way in per look
## Steps before a piece that was hidden is checked again: meanwhile the
## looks go to others, farther off (a heap behind a corner must not keep
## the orb from what it can see).
const SIGHT_AGAIN := 20
const PULL := 10.0  ## m/s, the speed pieces come in at (heavy ones slower)
## Pieces do not come straight in: they rise (m per m still to go, up to
## RISE_MOST) and wind round the orb (m/s), so you see them coming.
const RISE := 0.3
const RISE_MOST := 1.4
const SWIRL := 3.0
const DWINDLE := 1.6  ## m from the orb: from there a piece shrinks into it
## A piece that has not come STEP_IN nearer in STUCK steps is stuck: if it
## is several shards it comes apart, and they come in one by one; a lone
## shard is let go for good.
const STUCK := 40
const STEP_IN := 0.25
const INFLOW := 1.5  ## m round the orb: where the streaks of air start from
const OPEN_TIME := 0.18  ## s to open
const CLOSE_TIME := 0.25  ## s to close, once you let go
const GLOW := Color(0.66, 0.5, 1.0)
const BALL := preload("res://shaders/orb.gdshader")
const HALO := preload("res://shaders/orb_halo.gdshader")

var structure: Structure
var eye: Node3D  ## it is held in front of this
var open := true  ## false once you have let go: it closes, then is gone
var swallowed := 0.0  ## m3 it has made disappear
var centre := Vector3.ZERO

var _grip: Array[Vector3i] = []  # on their way in: (piece, its serial, steps since it last came nearer)
var _mark := PackedFloat32Array()  # per entry of _grip: how far it was then (m)
var _refused := {}  # Vector2i(piece, serial): given up on
var _hidden := {}  # Vector2i(piece, serial): the step it is checked again from
var _steps := 0
var _grown := 0.0  # 0 closed, 1 fully open
var _pulse := 0.0  # it swells a little as it swallows
var _ball: MeshInstance3D
var _halo: MeshInstance3D
var _light: OmniLight3D
var _inflow: CPUParticles3D


func setup(s: Structure, from: Node3D) -> void:
	structure = s
	eye = from


func _ready() -> void:
	add_to_group("orb")
	var round := SphereMesh.new()
	round.radius = 1.0
	round.height = 2.0
	round.radial_segments = 24
	round.rings = 12
	_ball = _layer(round, BALL)
	_halo = _layer(round, HALO)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	add_child(_light)
	_inflow = Fx.make_inflow(int(Quality.pick(14, 20, 28)), SIZE + INFLOW)
	_inflow.color = Color(GLOW.r, GLOW.g, GLOW.b, 0.5)
	add_child(_inflow)
	centre = _hold_point()
	_show()


func _physics_process(delta: float) -> void:
	_steps += 1
	centre = centre.lerp(_hold_point(), 1.0 - exp(-14.0 * delta))
	if open:
		_draw_in()


func _process(delta: float) -> void:
	_pulse = move_toward(_pulse, 0.0, delta * 4.0)
	if open:
		_grown = move_toward(_grown, 1.0, delta / OPEN_TIME)
	else:
		_grown = move_toward(_grown, 0.0, delta / CLOSE_TIME)
		if _grown <= 0.0:
			queue_free()
	_show()


## You let go: what was on its way in falls back, and the orb closes.
func close() -> void:
	if not open:
		return
	open = false
	var p := structure.pieces
	for g in _grip:
		if p.alive[g.x] == 1 and p.serial_of(g.x) == g.y:
			p.let_go(g.x)
	for i in p.adrift:
		if p.alive[i] == 1 and p.gripped[i] == 1:
			p.let_go(i)
	p.adrift.clear()
	_grip.clear()
	_mark.clear()
	_inflow.emitting = false


func _layer(shape: Mesh, shader: Shader) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var m := MeshInstance3D.new()
	m.mesh = shape
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


## Where it is held: in front of the eye and a little below, never in a
## wall or in the ground.
func _hold_point() -> Vector3:
	var from := eye.global_position
	var dir := -eye.global_basis.z
	var out := HOLD
	var ray := PhysicsRayQueryParameters3D.create(
		from, from + dir * (out + SIZE), Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		out = clampf(from.distance_to(hit["position"]) - SIZE - 0.05, 0.6, out)
	var at := from + dir * out - eye.global_basis.y * LOW
	at.y = maxf(at.y, SIZE + 0.05)
	return at


## Pieces on their way come nearer and are swallowed when they arrive; now
## and then it looks around for more.
func _draw_in() -> void:
	var p := structure.pieces
	var near := SIZE * 0.6 + 0.1
	# The parts of what broke on its way in are still in its grip.
	for i in p.adrift:
		var held := Vector3i(i, p.serial_of(i), 0)
		if p.alive[i] == 1 and p.gripped[i] == 1 and not _grip.has(held):
			_grip.append(held)
			_mark.append(centre.distance_to(p.transform_of(i).origin))
	p.adrift.clear()
	for k in range(_grip.size() - 1, -1, -1):
		var g := _grip[k]
		var i := g.x
		if p.alive[i] == 0 or p.serial_of(i) != g.y:
			_drop(k)  # it broke up on the way: its parts are adrift
			continue
		var to := centre - p.transform_of(i).origin
		var d := to.length()
		if d < near:
			_drop(k)
			swallowed += p.mass[i] / Structure.DENSITY
			p.take(i)
			_pulse = 1.0
			continue
		var waited := g.z + 1
		if d < _mark[k] - STEP_IN:
			_mark[k] = d
			waited = 0
		if waited > STUCK:
			_drop(k)
			if p.members[i].size() > 1:
				p.break_up(i)
			else:
				_refused[Vector2i(i, g.y)] = true
				p.let_go(i)
			continue
		_grip[k] = Vector3i(i, g.y, waited)
		var speed := PULL / (1.0 + p.mass[i] / 4000.0)
		var size := 0.15 + 0.85 * clampf((d - near) / DWINDLE, 0.0, 1.0)
		var way := (to + Vector3.UP * minf(d * RISE, RISE_MOST)).normalized() * speed
		way += Vector3.UP.cross(to / d) * SWIRL * clampf(d / 4.0, 0.0, 1.0)
		p.drag(i, p.velocity_of(i).lerp(way, 0.3), size)
	if _steps % LOOK_EVERY == 0 and _grip.size() < GRIP:
		_look_around()


## Takes hold of the nearest loose pieces it can see.
func _look_around() -> void:
	var p := structure.pieces
	var found: Array[Vector2] = []  # (distance, piece)
	for i in p.top:
		if p.alive[i] == 0 or p.gripped[i] == 1:
			continue
		var d := p.transform_of(i).origin.distance_squared_to(centre)
		var key := Vector2i(i, p.serial_of(i))
		if d < REACH * REACH and not _refused.has(key) and _hidden.get(key, 0) <= _steps:
			found.append(Vector2(d, i))
	found.sort()
	var space := get_world_3d().direct_space_state
	var taken := 0
	var tries := 0
	for f in found:
		if taken >= NEW_PER_LOOK or tries >= SIGHT_TRIES or _grip.size() >= GRIP:
			break
		var i := int(f.y)
		tries += 1
		# Not what is behind a wall: it would only press against it.
		var ray := PhysicsRayQueryParameters3D.create(
			centre, p.transform_of(i).origin, Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
		)
		if not space.intersect_ray(ray).is_empty():
			if _hidden.size() > 500:
				_hidden.clear()
			_hidden[Vector2i(i, p.serial_of(i))] = _steps + SIGHT_AGAIN
			continue
		p.grip(i)
		_grip.append(Vector3i(i, p.serial_of(i), 0))
		_mark.append(sqrt(f.x))
		taken += 1


func _drop(k: int) -> void:
	_grip.remove_at(k)
	_mark.remove_at(k)


func _show() -> void:
	var size := SIZE * _grown * (1.0 + 0.18 * _pulse)
	var power := 1.0 + 0.9 * _pulse
	_ball.global_transform = Transform3D(Basis().scaled(Vector3.ONE * maxf(size, 0.001)), centre)
	_halo.global_transform = Transform3D(Basis().scaled(Vector3.ONE * maxf(size * 2.1, 0.001)), centre)
	(_ball.material_override as ShaderMaterial).set_shader_parameter("power", power)
	(_halo.material_override as ShaderMaterial).set_shader_parameter("power", power * _grown)
	_light.global_position = centre
	_light.light_energy = 1.1 * _grown * power
	_inflow.global_position = centre
