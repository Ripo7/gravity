class_name BlobShadow
extends MeshInstance3D
## A round shadow on the ground under a body: the sun casts none (its
## shadows are what cost a phone the most), and without one a body seems to
## float. It stays on the ground when the body jumps, and gets smaller and
## fainter the higher the body is.

## How wide it is (m) under a body that stands.
const WIDE := 1.7
## It lies this far above the ground (m), so that the two do not flicker.
const ABOVE := 0.03
## The ground is looked for this far below the body (m), and the shadow is
## gone when the body is HIGH m above it.
const BELOW := 30.0
const HIGH := 8.0

## Whose shadow it is.
var body: Node3D

var _ray := PhysicsRayQueryParameters3D.new()


func _init(of: Node3D) -> void:
	body = of
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0)])
	var round := GradientTexture2D.new()
	round.gradient = fade
	round.fill = GradientTexture2D.FILL_RADIAL
	round.fill_from = Vector2(0.5, 0.5)
	round.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = round
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flat := PlaneMesh.new()
	flat.size = Vector2(WIDE, WIDE)
	flat.material = mat
	mesh = flat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It lies on the ground, wherever the body is and however it is turned.
	top_level = true
	_ray.collision_mask = Layers.WORLD


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(body):
		return
	var from := body.global_position + Vector3.UP * 0.5
	_ray.from = from
	_ray.to = from + Vector3.DOWN * BELOW
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	visible = not hit.is_empty()
	if not visible:
		return
	var ground: Vector3 = hit["position"]
	var near := clampf(1.0 - (body.global_position.y - ground.y) / HIGH, 0.0, 1.0)
	global_transform = Transform3D(
		Basis().scaled(Vector3.ONE * lerpf(0.5, 1.0, near)), ground + Vector3.UP * ABOVE
	)
	transparency = 1.0 - near
