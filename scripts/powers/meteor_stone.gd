class_name MeteorStone
extends RigidBody3D
## The huge mysterious stone dropped by the portal. Heavy and fast: it
## smashes the blocks it lands on, shoves debris aside and crushes the
## unwary. It is destructible too: hard hits and black holes wear it down
## until it bursts into heavy chunks.

const SHADER := preload("res://shaders/stone.gdshader")
const DENSITY := 900.0
const LIFETIME := 18.0
const MAX_ALIVE := 40
const IMPACT_DROP := 4.0  ## m/s of sudden slow-down that counts as a hit
const IMPACT_MIN := 6.0
const CHUNKS := 18
const HP_PER_SPEED := 2.2  ## hit points lost per m/s of impact

var size := 2.0
var hp := PowerDefs.PORTAL_STONE_HP
var _mat: ShaderMaterial
var _mesh: MeshInstance3D
var _prev_speed := 0.0
var _age := 0.0
var _last_hit := -1.0
var _hits := 0
var _world: GameWorld


static func make(world: GameWorld, at: Vector3, stone_size: float, rng: RandomNumberGenerator) -> MeteorStone:
	var s := MeteorStone.new()
	s._world = world
	s.size = stone_size
	s.position = at
	s._build(rng)
	return s


func _build(rng: RandomNumberGenerator) -> void:
	# A jagged bipyramid: two apexes around a ring of jittered points.
	var pts := PackedVector3Array()
	var ring := 6 + rng.randi() % 3
	var half_len := size * 0.5
	var r := size * 0.32
	pts.append(Vector3(rng.randf_range(-0.1, 0.1) * r, half_len, rng.randf_range(-0.1, 0.1) * r))
	pts.append(Vector3(rng.randf_range(-0.1, 0.1) * r, -half_len * rng.randf_range(0.7, 1.0), 0))
	for k in ring:
		var a := TAU * k / ring + rng.randf_range(-0.2, 0.2)
		var rr := r * rng.randf_range(0.75, 1.15)
		pts.append(Vector3(cos(a) * rr, rng.randf_range(-0.2, 0.25) * half_len, sin(a) * rr))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in ring:
		var a := pts[2 + k]
		var b := pts[2 + (k + 1) % ring]
		_tri(st, pts[0], b, a)
		_tri(st, pts[1], a, b)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	_mesh = mi
	mi.mesh = mesh
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("seed", rng.randf())
	mi.material_override = _mat
	add_child(mi)
	mass = maxf(size * size * size * 0.25 * DENSITY, 200.0)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.9
	physics_material_override.bounce = 0.05
	collision_layer = DebrisSystem.LAYER_DEBRIS
	collision_mask = (
		DebrisSystem.LAYER_WORLD
		| DebrisSystem.LAYER_STRUCTURES
		| DebrisSystem.LAYER_DEBRIS
		| DebrisSystem.LAYER_PLAYER
	)
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	angular_damp = 0.4


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


func _ready() -> void:
	add_to_group("meteor_stone")
	var all := get_tree().get_nodes_in_group("meteor_stone")
	if all.size() > MAX_ALIVE:
		(all[0] as MeteorStone).vanish()


func _physics_process(delta: float) -> void:
	_age += delta
	var speed := linear_velocity.length()
	var drop := _prev_speed - speed
	if (
		drop > IMPACT_DROP
		and _prev_speed > IMPACT_MIN
		and get_contact_count() > 0
		and _age - _last_hit > 0.15
	):
		_impact(_prev_speed)
	_prev_speed = speed
	if _hits > 0:
		_mat.set_shader_parameter("glow", maxf(0.0, 1.0 - (_age - _last_hit) * 0.5))
	if global_position.y < DebrisSystem.KILL_Y:
		vanish()
	elif _age > LIFETIME:
		shatter()


func _impact(speed: float) -> void:
	_last_hit = _age
	_hits += 1
	var at := global_position - Vector3(0, size * 0.4, 0)
	if _world == null:
		return
	# Damage scales with momentum; a big stone at speed flattens a storey.
	var damage := clampf(speed * mass / 700.0, 3.0, 90.0)
	var reach := size * 1.0 + 0.8
	_world.structures.apply_impact(at, reach, damage)
	_world.shove_debris(at, reach * 1.8, speed * 0.35)
	_world.stone_landed(at, size, speed)
	damage(speed * HP_PER_SPEED)


## Wears the stone down; at zero it bursts.
func damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		shatter.call_deferred()


## Bursts into heavy dark chunks that keep the stone's momentum.
func shatter() -> void:
	if is_queued_for_deletion() or not is_inside_tree() or _world == null:
		return
	remove_from_group("meteor_stone")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var v := linear_velocity
	for k in CHUNKS:
		var dir := (
			Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		)
		var at := global_position + dir * size * rng.randf_range(0.05, 0.28)
		var edge := size * rng.randf_range(0.13, 0.24)
		var chunk := Vector3(edge, edge * rng.randf_range(0.6, 1.0), edge * rng.randf_range(0.7, 1.2))
		var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		_world.debris.spawn(
			Transform3D(basis, at),
			chunk,
			v * 0.5 + dir * rng.randf_range(2.0, 6.0),
			dir.cross(Vector3.UP) * 4.0,
			0.6,
			0.38,
			Materials.Kind.CONCRETE
		)
	if _world.dust:
		_world.dust.puff(global_position, size * 0.7, Materials.Kind.CONCRETE, 18)
	Sfx.play("break_concrete", global_position, 6.0, 0.6)
	queue_free()


## Sinks into violet dust and disappears.
func vanish() -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return
	remove_from_group("meteor_stone")
	set_deferred("freeze", true)
	collision_layer = 0
	collision_mask = 0
	if _world and _world.dust:
		_world.dust.puff(global_position, size * 0.6, Materials.Kind.ICE, 10)
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3.ONE * 0.01, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
