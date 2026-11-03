class_name PowerBall
extends Node3D
## The thrown ball. Moves with a sphere shape-cast each physics step and
## detonates a GravityBlast on the first hit (or when its fuse runs out).

const GRAVITY := 2.5
const FUSE := 3.5
const HIT_MASK := DebrisSystem.LAYER_WORLD | DebrisSystem.LAYER_STRUCTURES | DebrisSystem.LAYER_DEBRIS

var params: BlastParams
var velocity := Vector3.ZERO
var _age := 0.0
var _query := PhysicsShapeQueryParameters3D.new()
var _material: Material


func setup(p: BlastParams, start: Vector3, v: Vector3, material: Material) -> void:
	params = p
	position = start
	velocity = v
	_material = material


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = params.ball_radius
	sphere.height = params.ball_radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Palette.VIOLET
	light.light_energy = 1.0 + params.charge * 2.0
	light.omni_range = 2.0 + params.charge * 4.0
	add_child(light)
	add_child(Fx.make_trail(params.ball_radius))
	var shape := SphereShape3D.new()
	shape.radius = params.ball_radius
	_query.shape = shape
	_query.collision_mask = HIT_MASK
	_query.collide_with_bodies = true
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player:
		_query.exclude = [player.get_rid()]


func _physics_process(delta: float) -> void:
	_age += delta
	velocity.y -= GRAVITY * delta
	var motion := velocity * delta
	_query.transform = Transform3D(Basis(), global_position)
	_query.motion = motion
	var space := get_world_3d().direct_space_state
	var result := space.cast_motion(_query)
	var safe: float = result[0]
	if safe < 1.0:
		global_position += motion * safe
		_detonate()
		return
	global_position += motion
	if _age > FUSE:
		_detonate()


func _detonate() -> void:
	var world := GameWorld.of(self)
	if world:
		world.detonate(global_position, params, velocity)
	queue_free()
