class_name IceShield
extends AnimatableBody3D
## Shield power: a slab of black ice bursts out of the ground in front of the
## player. It blocks debris, stones and falling pieces until it has taken
## too many hits (or melts away), then shatters into black ice shards.

const SHADER := preload("res://shaders/ice_shield.gdshader")
const RISE_TIME := 0.22
const THICKNESS := 0.7
## Hits slower than this (m/s, relative) do not wear the shield down.
const HIT_MIN_SPEED := 3.0

var tier := 0
var width := 4.0
var height := 3.0
var hp := 300.0
var max_hp := 300.0
var _world: GameWorld
var _rest: Transform3D
var _t := 0.0
var _mat: ShaderMaterial
var _area: Area3D
var _recent := {}  # body rid -> time of last counted hit
var _broken := false
var _flash := 0.0


func setup(world: GameWorld, base: Transform3D, size_tier: int) -> void:
	_world = world
	tier = size_tier
	width = PowerDefs.SHIELD_WIDTH[tier]
	height = PowerDefs.SHIELD_HEIGHT[tier]
	max_hp = PowerDefs.SHIELD_HP[tier]
	hp = max_hp
	# `base` sits on the ground, facing the player (-Z toward the threat).
	_rest = base.translated_local(Vector3(0, height * 0.5, 0))
	transform = _rest.translated_local(Vector3(0, -height - 0.2, 0))


func _ready() -> void:
	add_to_group("ice_shield")
	sync_to_physics = true
	collision_layer = DebrisSystem.LAYER_STRUCTURES
	collision_mask = 0
	var size := Vector3(width, height, THICKNESS)
	var box := BoxShape3D.new()
	box.size = size
	var col := CollisionShape3D.new()
	col.shape = box
	add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = size
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("size", size)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	# Slightly larger sensor that notices what slams into the slab.
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = DebrisSystem.LAYER_DEBRIS
	var sensor := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	# Deep along its facing so fast pieces are seen before they touch.
	sbox.size = size + Vector3(0.4, 0.4, 3.0)
	sensor.shape = sbox
	_area.add_child(sensor)
	add_child(_area)
	_area.body_shape_entered.connect(_on_body_entered)
	Sfx.play("ice_rise", _rest.origin, -4.0 + tier * 3.0, 1.1 - tier * 0.12)
	if _world and _world.dust:
		_world.dust.puff(_rest.origin - Vector3(0, height * 0.5, 0), width * 0.4, Materials.Kind.CONCRETE, 14)


func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / RISE_TIME, 0.0, 1.0)
	var start := _rest.translated_local(Vector3(0, -height - 0.2, 0))
	global_transform = start.interpolate_with(_rest, ease(k, 0.35))
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


func _on_body_entered(rid: RID, body: Node, _bs: int, _ls: int) -> void:
	var now := _t
	if now - float(_recent.get(rid, -10.0)) < 0.4:
		return
	_recent[rid] = now
	var motion := Hazards.motion_of(_world, rid, body)
	if motion.is_empty():
		return
	var v: Vector3 = motion["velocity"]
	# Only what flies toward the slab counts, from either face.
	var n := global_basis.z
	var src: Vector3 = (body as Node3D).global_position if body is Node3D else _debris_position(rid)
	var side := signf((src - global_position).dot(n)) if src != Vector3.INF else 1.0
	var closing := -v.dot(n) * side
	if closing < HIT_MIN_SPEED:
		return
	hit(float(motion["mass"]) * closing / 12.0)


func _debris_position(rid: RID) -> Vector3:
	var i := _world.debris.index_of(rid) if _world else -1
	return _world.debris.position_of(i) if i >= 0 else Vector3.INF


## Breaks into black ice shards that stay in the world as debris.
func shatter() -> void:
	if _broken:
		return
	_broken = true
	Sfx.play("ice_break", global_position, -2.0 + tier * 3.0)
	if _world:
		var size := Vector3(width, height, THICKNESS)
		var count := clampi(int(width * height * 1.2), 6, 18)
		for piece: AABB in Fracture.pattern(size, count, tier):
			var xf := global_transform * Transform3D(Basis(), piece.get_center())
			var kick := (global_transform.basis.z * randf_range(-1.0, 1.0) + Vector3.UP) * 1.5
			var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 4.0
			_world.debris.spawn(xf, piece.size * 0.97, kick, spin, 0.3, 1.0, Materials.Kind.ICE)
		if _world.dust:
			_world.dust.chips(global_position, width * 0.5, Materials.Kind.ICE, 6.0, 24)
	queue_free()
