class_name Shockwave
extends Node3D
## Shock wave: a blast of air out of your hands, along where you look. Its
## front runs out to RANGE in a cone. Standing shards it reaches are torn
## out where it is strong (close, and near its axis) and only cracked where
## it is weak; what it hits takes most of it, so a wall shelters what is
## behind. Loose pieces are thrown away from you.

const RANGE := 16.0  ## m
const SPEED := 45.0  ## m/s
const ANGLE := 32.0  ## degrees either side of where you look
## Force at your hands on the axis (1 tears a shard out, see
## Structure.strike); it fades to nothing at RANGE and to half at the edge.
const FORCE := 3.4
## Speed (m/s) given to what it tears out or pushes, at your hands.
const THROW := 17.0
## The cone is watched through a grid of BINS x BINS windows: what the blast
## has already hit in a window weakens it for whatever is behind.
const BINS := 14
const PASS_HELD := 0.15  ## share that goes on behind a shard that held
const PASS_TORN := 0.5  ## and behind one it tore out
const AIR := Color(0.85, 0.92, 1.0)

var origin := Vector3.ZERO
var direction := Vector3.FORWARD
var structure: Structure
## How many shards this wave tore out (for tests and the scripted runs).
var torn := 0

var _basis := Basis()
var _tan := 0.0
var _cos := 0.0
var _front := 0.0
var _done := 0.0
var _t := 0.0
var _reached: Array[Vector2] = []  # (distance, shard): standing shards in the cone, nearest first
var _next := 0
var _pass := PackedFloat32Array()


## `at`: where it leaves your hands; `dir`: where you look.
func setup(s: Structure, at: Vector3, dir: Vector3) -> void:
	structure = s
	origin = at
	direction = dir.normalized()


func _ready() -> void:
	add_to_group("shockwave")
	_tan = tan(deg_to_rad(ANGLE))
	_cos = cos(deg_to_rad(ANGLE))
	var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.BACK
	_basis = Basis.looking_at(direction, up)
	_pass.resize(BINS * BINS)
	_pass.fill(1.0)
	if structure:
		for i in structure.count:
			if structure.held[i] == 0:
				continue
			var off := structure.centroid[i] - origin
			var d := off.length()
			if d < RANGE and (d < structure.radius[i] or off.dot(direction) > d * _cos * 0.92):
				_reached.append(Vector2(d, i))
		_reached.sort()
	var xf := Transform3D(_basis, origin)
	var time := RANGE / SPEED
	var wave := BlastWave.spawn(self, xf, 0.5, RANGE, time * 1.5, AIR, ANGLE + 4.0)
	(wave.material_override as ShaderMaterial).set_shader_parameter("glow", 1.4)
	var streaks := Fx.make_streaks(int(Quality.pick(24, 36, 48)), ANGLE)
	add_child(streaks)
	streaks.global_transform = xf
	streaks.emitting = true
	var cam := get_viewport().get_camera_3d() as CameraShake
	if cam:
		cam.add_trauma(0.3)


func _physics_process(delta: float) -> void:
	_t += delta
	_front = minf(_front + SPEED * delta, RANGE)
	if structure and _done < _front:
		_hit_pieces(_done, _front)
		_hit_standing(_front)
		_done = _front
	if _t > RANGE / SPEED * 1.5 + 0.1:
		queue_free()


## How hard it hits `d` metres out (1 at your hands, 0 at RANGE).
static func strength(d: float) -> float:
	return pow(clampf(1.0 - d / RANGE, 0.0, 1.0), 1.5)


## The standing shards the front has reached, nearest first.
func _hit_standing(far: float) -> void:
	var s := structure
	while _next < _reached.size() and _reached[_next].x <= far:
		var d := _reached[_next].x
		var i := int(_reached[_next].y)
		_next += 1
		if s.held[i] == 0:
			continue
		var off := s.centroid[i] - origin
		var away := off / maxf(d, 0.01)
		var window := _window(off, s.radius[i] * 0.7)
		var force := FORCE * strength(d) * _side(away) * _let_through(window)
		var speed := THROW * sqrt(strength(d)) * randf_range(0.6, 1.1)
		s.strike(i, force, away * speed + Vector3.UP * 1.5)
		if s.held[i] == 0:
			torn += 1
		_block(window, PASS_HELD if s.held[i] == 1 else PASS_TORN)


## Loose pieces between `near` and `far` are thrown away from you; heavy
## ones less.
func _hit_pieces(near: float, far: float) -> void:
	var p := structure.pieces
	for i in p.alive.size():
		if p.alive[i] == 0:
			continue
		var off := p.transform_of(i).origin - origin
		var d := off.length()
		if d <= near or d > far or off.dot(direction) < d * _cos:
			continue
		var away := off / maxf(d, 0.01)
		var push := THROW * strength(d) * _let_through(_window(off, p.reach[i] * 0.5))
		push /= 1.0 + p.mass[i] / 600.0
		if push < 0.6:
			continue
		var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * push * 0.4
		p.push(i, away * push + Vector3.UP * push * 0.2, spin)


## 1 on the axis, 0.5 at the edge of the cone.
func _side(away: Vector3) -> float:
	return lerpf(0.5, 1.0, smoothstep(_cos, 1.0, away.dot(direction)))


## The windows (x0, y0, x1, y1, inclusive) covered by something `size`
## metres wide at `off` from the origin.
func _window(off: Vector3, size: float) -> Rect2i:
	var local := off * _basis  # the cone looks down -Z
	var depth := maxf(-local.z, 0.05)
	var u := Vector2(local.x, local.y) / (depth * _tan)
	var r := size / (depth * _tan)
	var lo := ((u - Vector2(r, r)) * 0.5 + Vector2(0.5, 0.5)) * BINS
	var hi := ((u + Vector2(r, r)) * 0.5 + Vector2(0.5, 0.5)) * BINS
	var a := Vector2i(clampi(floori(lo.x), 0, BINS - 1), clampi(floori(lo.y), 0, BINS - 1))
	var b := Vector2i(clampi(floori(hi.x), 0, BINS - 1), clampi(floori(hi.y), 0, BINS - 1))
	return Rect2i(a, b - a)


## Share of the blast still coming through these windows.
func _let_through(window: Rect2i) -> float:
	var sum := 0.0
	for y in range(window.position.y, window.end.y + 1):
		for x in range(window.position.x, window.end.x + 1):
			sum += _pass[y * BINS + x]
	return sum / ((window.size.x + 1) * (window.size.y + 1))


func _block(window: Rect2i, share: float) -> void:
	for y in range(window.position.y, window.end.y + 1):
		for x in range(window.position.x, window.end.x + 1):
			_pass[y * BINS + x] *= share
