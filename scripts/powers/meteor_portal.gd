class_name MeteorPortal
extends Node3D
## Portal power: a horizontal portal opens high above the target zone and
## huge stones fall out of it onto everything inside the zone.

const SHADER := preload("res://shaders/portal.gdshader")
const OPEN_TIME := 0.45
const CLOSE_TIME := 0.4

var radius := 3.0
var stones_left := 0
var _world: GameWorld
var _target := Vector3.ZERO
var _height := 25.0
var _disc: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _t := 0.0
var _next_stone := 0.0
var _gap := 0.1
var _closing := -1.0
var _beam: MeshInstance3D
var _zone: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func setup(world: GameWorld, target: Vector3) -> void:
	_world = world
	_target = target
	radius = PowerDefs.PORTAL_RADIUS
	stones_left = PowerDefs.PORTAL_STONES
	_height = PowerDefs.PORTAL_HEIGHT
	_gap = PowerDefs.PORTAL_SPREAD / maxf(stones_left - 1, 1)
	_next_stone = OPEN_TIME
	# Never open inside the ground, and keep a clear drop above tall targets.
	position = Vector3(target.x, maxf(target.y, 0.0) + _height, target.z)
	_rng.randomize()


func _ready() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	disc.radial_segments = 64
	_disc = MeshInstance3D.new()
	_disc.mesh = disc
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("violet", Palette.VIOLET)
	_disc.material_override = _mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.scale = Vector3(0.01, 1, 0.01)
	add_child(_disc)
	_light = OmniLight3D.new()
	_light.light_color = Palette.VIOLET
	_light.omni_range = radius * 2.5
	_light.light_energy = 0.0
	_light.position = Vector3(0, -1.0, 0)
	add_child(_light)
	_build_markers()
	Sfx.play("portal", global_position, 4.0, 0.8)


## A thin light beam down to the target and a ring on the ground, so the
## drop zone reads even when the portal itself is off screen.
func _build_markers() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Palette.VIOLET, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var drop := global_position.y - _target.y
	var beam := CylinderMesh.new()
	beam.top_radius = 0.18
	beam.bottom_radius = 0.18
	beam.height = drop
	beam.radial_segments = 8
	_beam = MeshInstance3D.new()
	_beam.mesh = beam
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0, -drop * 0.5, 0)
	add_child(_beam)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.93
	ring.outer_radius = 1.0
	ring.rings = 64
	_zone = MeshInstance3D.new()
	_zone.mesh = ring
	_zone.material_override = m
	_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.position = Vector3(0, -drop + 0.06, 0)
	_zone.scale = Vector3(radius, 1, radius)
	add_child(_zone)


func _process(delta: float) -> void:
	_t += delta
	var d := radius * 2.2
	if _closing < 0.0:
		var k := ease(clampf(_t / OPEN_TIME, 0.0, 1.0), 0.3)
		_disc.scale = Vector3(d * k, 1, d * k)
		_light.light_energy = 3.0 * k
	else:
		var k := clampf((_t - _closing) / CLOSE_TIME, 0.0, 1.0)
		_disc.scale = Vector3(d * (1.0 - k), 1, d * (1.0 - k))
		_light.light_energy = 3.0 * (1.0 - k)
		_beam.visible = false
		_zone.visible = false
		if k >= 1.0:
			queue_free()
		return
	_disc.rotation.y += delta * 0.8
	while stones_left > 0 and _t >= _next_stone:
		_drop_stone()
		stones_left -= 1
		_next_stone += _gap * _rng.randf_range(0.6, 1.4)
	if stones_left == 0 and _t > _next_stone + 0.5:
		_closing = _t


func _drop_stone() -> void:
	if _world == null:
		return
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * radius * 0.8
	var at := global_position + Vector3(cos(a) * r, -1.5, sin(a) * r)
	var size: float = PowerDefs.PORTAL_STONE_SIZE * _rng.randf_range(0.8, 1.2)
	var stone := MeteorStone.make(_world, at, size, _rng)
	_world.add_child(stone)
	stone.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	stone.linear_velocity = Vector3(0, -_rng.randf_range(10.0, 16.0), 0)
	stone.angular_velocity = Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * 3.0
