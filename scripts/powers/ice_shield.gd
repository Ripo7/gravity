class_name IceShield
extends AnimatableBody3D
## Shield power: a curved shell of black ice, close to a half dome but
## lumpy and uneven, bursts out of the ground around the front of the
## player. It blocks debris and falling pieces until it has taken too many
## hits (or melts away), then shatters into black ice shards.

const SHADER := preload("res://shaders/ice_shield.gdshader")
const RISE_TIME := 0.3
## Hits slower than this (m/s, toward the shell) do not wear it down.
const HIT_MIN_SPEED := 3.0
## Mesh grid (around, up) and collision panels (around, up).
const MESH_GRID := Vector2i(18, 9)
const PANELS := Vector2i(8, 4)
## The top stops short of closing over the player's head.
const TOP_ELEVATION := deg_to_rad(76.0)

var radius := 2.7
var height := 4.8
var arc := deg_to_rad(200.0)
var hp := 300.0
var max_hp := 300.0
var _world: GameWorld
var _rest: Transform3D
var _t := 0.0
var _mat: ShaderMaterial
var _area: Area3D
var _recent := {}  # body rid -> time of last counted hit
var _inside := {}  # body rid -> its node (or null) while in the sensor
var _broken := false
var _flash := 0.0
var _solid := false
var _panels: Array[CollisionShape3D] = []
var _rng := RandomNumberGenerator.new()
var _phase := Vector3.ZERO  # random lumps, so no two shields look alike


func setup(world: GameWorld, base: Transform3D) -> void:
	_world = world
	radius = PowerDefs.SHIELD_RADIUS
	height = PowerDefs.SHIELD_HEIGHT
	arc = deg_to_rad(PowerDefs.SHIELD_ARC)
	max_hp = PowerDefs.SHIELD_HP
	hp = max_hp
	# `base` is the player's feet, -Z the way they look.
	_rest = base
	transform = _rest.translated_local(Vector3(0, -height - 0.3, 0))
	_rng.randomize()
	_phase = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf_range(0.92, 1.08))


func _ready() -> void:
	add_to_group("ice_shield")
	sync_to_physics = true
	# Before the debris: hits are judged on how fast things came in.
	process_physics_priority = -5
	collision_layer = DebrisSystem.LAYER_STRUCTURES
	collision_mask = 0
	_build_mesh()
	_build_panels()
	# Sensor around the whole shell: notices what flies at it.
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = DebrisSystem.LAYER_DEBRIS
	var sensor := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, height) + 2.0
	sensor.shape = sphere
	_area.add_child(sensor)
	add_child(_area)
	_area.body_shape_entered.connect(_on_body_entered)
	_area.body_shape_exited.connect(_on_body_exited)
	Sfx.play("ice_rise", _rest.origin, 3.0, 0.75)
	if _world and _world.dust:
		_world.dust.puff(_rest.origin + _rest.basis.z * -radius, radius * 0.8, Materials.Kind.CONCRETE, 18)


## Point on the shell at azimuth `a` (0 = straight ahead) and elevation `e`,
## with smooth lumps so it is never a perfect dome.
func shell_point(a: float, e: float, lumpy := true) -> Vector3:
	var r := radius
	var h := height
	if lumpy:
		var lump := sin(a * 3.0 + _phase.x) * 0.07 + sin(e * 4.0 + a * 2.0 + _phase.y) * 0.05
		r *= 1.0 + lump
		h *= _phase.z * (1.0 + 0.6 * lump) if e > 0.5 else 1.0 + 0.4 * lump
	var flat := Vector3(sin(a), 0, -cos(a))
	return flat * r * cos(e) + Vector3.UP * h * sin(e)


## Outward normal of the (smooth) shell at `a`, `e`.
func shell_normal(a: float, e: float) -> Vector3:
	var p := shell_point(a, e, false)
	return Vector3(p.x / (radius * radius), p.y / (height * height), p.z / (radius * radius)).normalized()


func _top(a: float) -> float:
	# A ragged upper edge: higher in the middle, broken toward the sides.
	var side := absf(a) / (arc * 0.5)
	return TOP_ELEVATION * (1.0 - 0.35 * side * side) + sin(a * 5.0 + _phase.x) * 0.06


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := MESH_GRID.x
	var ne := MESH_GRID.y
	var grid: Array[PackedVector3Array] = []
	for i in na + 1:
		var a := -arc * 0.5 + arc * i / na
		var col := PackedVector3Array()
		var top := _top(a)
		for j in ne + 1:
			var e := top * j / ne
			var p := shell_point(a, e)
			# Facets: jitter the inner vertices a little.
			if j > 0 and j < ne and i > 0 and i < na:
				p += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.09
			col.append(p)
		grid.append(col)
	for i in na:
		for j in ne:
			var a := grid[i][j]
			var b := grid[i + 1][j]
			var c := grid[i + 1][j + 1]
			var d := grid[i][j + 1]
			_tri(st, a, c, b)
			_tri(st, a, d, c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


## Thin box panels tangent to the shell: what debris actually collides with.
func _build_panels() -> void:
	var da := arc / PANELS.x
	for i in PANELS.x:
		var a := -arc * 0.5 + da * (i + 0.5)
		var de := _top(a) / PANELS.y
		for j in PANELS.y:
			var e := de * (j + 0.5)
			var n := shell_normal(a, e)
			var along := Vector3(cos(a), 0, sin(a))
			var up := n.cross(along).normalized()
			var lo := shell_point(a, e - de * 0.5, false)
			var hi := shell_point(a, e + de * 0.5, false)
			var size := Vector3(
				radius * cos(e) * da * 1.15 + 0.2, lo.distance_to(hi) * 1.1 + 0.15, PowerDefs.SHIELD_THICKNESS
			)
			var box := BoxShape3D.new()
			box.size = size
			var col := CollisionShape3D.new()
			col.shape = box
			col.transform = Transform3D(Basis(along, up, n), shell_point(a, e, false))
			col.disabled = true  # solid once it has risen
			add_child(col)
			_panels.append(col)


func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / RISE_TIME, 0.0, 1.0)
	var start := _rest.translated_local(Vector3(0, -height - 0.3, 0))
	global_transform = start.interpolate_with(_rest, ease(k, 0.35))
	if k >= 1.0 and not _solid:
		_solid = true
		for p in _panels:
			p.disabled = false
	_check_hits()
	_mat.set_shader_parameter("damage", 1.0 - hp / max_hp)
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_mat.set_shader_parameter("flash", _flash)
	if _t > PowerDefs.SHIELD_LIFETIME:
		shatter()


## Takes `amount` damage (momentum-like units). Shatters at zero.
func hit(amount: float) -> void:
	if _broken or amount <= 0.0:
		return
	hp -= amount
	_flash = 1.0
	Sfx.play("ice_hit", global_position, -10.0 + minf(amount / 40.0, 8.0))
	if hp <= 0.0:
		shatter()


## True when world point `p` is on the outer side of the shell, within its
## arc: things there that fly inward hit the ice.
func is_outside(p: Vector3) -> bool:
	var q := global_transform.affine_inverse() * p
	if q.y < -0.5 or q.y > height + 1.0:
		return false
	var a := atan2(q.x, -q.z)
	if absf(a) > arc * 0.5 + 0.2:
		return false
	return Vector3(q.x / radius, q.y / height, q.z / radius).length() > 0.8


func _on_body_entered(rid: RID, body: Node, _bs: int, _ls: int) -> void:
	_inside[rid] = body


func _on_body_exited(rid: RID, _body: Node, _bs: int, _ls: int) -> void:
	_inside.erase(rid)


## Every step, what is about to touch the shell from outside and moves at
## it wears it down: pieces dropping on it from above, falling floors and
## pieces that were already near it count too, not only what flies in.
func _check_hits() -> void:
	if not _solid or _broken or _world == null:
		return
	for rid: RID in _inside.keys():
		if _t - float(_recent.get(rid, -10.0)) < 0.4:
			continue
		var body: Object = _inside[rid]
		var motion := Hazards.motion_of(_world, rid, body)
		if motion.is_empty():
			continue
		var src := _source_point(rid, body)
		if src == Vector3.INF or not is_outside(src):
			continue
		var q := global_transform.affine_inverse() * src
		var e := Vector3(q.x / radius, maxf(q.y, 0.0) / height, q.z / radius)
		if e.length() > 1.45:
			continue  # not at the shell yet
		var n := global_basis * e.normalized()
		var v: Vector3 = motion["velocity"]
		var closing := -v.dot(n)
		if closing < HIT_MIN_SPEED:
			continue
		_recent[rid] = _t
		hit(float(motion["mass"]) * closing / 12.0)


func _source_point(rid: RID, body: Object) -> Vector3:
	if body is Node3D:
		return (body as Node3D).global_position
	var i := _world.debris.index_of(rid)
	if i >= 0:
		return _world.debris.position_of(i)
	return _world.structures.cluster_point(rid, global_position + Vector3.UP * height * 0.5)


## Breaks into black ice shards that stay in the world as debris, thrown
## outward so they do not rain on the player inside.
func shatter() -> void:
	if _broken:
		return
	_broken = true
	Sfx.play("ice_break", global_position, 4.0)
	if _world:
		for col in _panels:
			var size := (col.shape as BoxShape3D).size
			var xf := global_transform * col.transform
			var out := xf.basis.z
			# Fewer, bigger shards on phones: 32 panels add up fast.
			for piece: AABB in Fracture.pattern(size, int(Quality.pick(2, 4, 6)), 2, -1, false):
				var at := xf * piece.get_center()
				var kick := out * randf_range(2.5, 4.5) + Vector3.UP * 1.0
				var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 4.0
				var shard := Transform3D(xf.basis, at)
				_world.debris.spawn(shard, piece.size * 0.95, kick, spin, 0.3, 1.0, Materials.Kind.ICE)
		if _world.dust:
			_world.dust.chips(
				global_position + Vector3.UP * height * 0.4, radius, Materials.Kind.ICE, 6.0, 30
			)
	queue_free()
