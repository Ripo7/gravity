class_name PowerHand
extends Node3D
## Charge-and-throw: hold "charge" to grow a ball in the hand, release to
## throw it. Charge maps to every blast parameter through BlastParams.

signal charge_changed(value: float)
signal thrown(params: BlastParams)

const PowerBallScript := preload("res://scripts/power/power_ball.gd")

@export var charge_time := 1.6  ## seconds to full charge
@export var cooldown := 0.22
@export var ball_material: Material

var charge := 0.0
var charging := false
var auto_input := false  ## true when a script (demo/bench) drives the hand
var _cooldown_left := 0.0
var _ball: MeshInstance3D
var _light: OmniLight3D
var _wobble := 0.0


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_ball = MeshInstance3D.new()
	_ball.mesh = sphere
	_ball.material_override = ball_material
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.visible = false
	add_child(_ball)
	_light = OmniLight3D.new()
	_light.light_color = Palette.VIOLET
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	add_child(_light)


func _process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not auto_input:
		var held := Input.is_action_pressed("charge") and _input_allowed()
		if held and not charging and _cooldown_left <= 0.0:
			begin_charge()
		elif not held and charging:
			release()
	if charging:
		charge = minf(charge + delta / charge_time, 1.0)
		charge_changed.emit(charge)
	_update_visual(delta)


func begin_charge() -> void:
	charging = true
	charge = 0.0


func release() -> void:
	if not charging:
		return
	charging = false
	var params := BlastParams.from_charge(_eased(charge))
	var cam := get_viewport().get_camera_3d()
	var dir := -cam.global_basis.z if cam else -global_basis.z
	var ball: Node3D = PowerBallScript.new()
	ball.setup(params, global_position, dir * params.throw_speed, ball_material)
	var world := GameWorld.of(self)
	if world:
		world.add_child(ball)
	else:
		get_tree().current_scene.add_child(ball)
	thrown.emit(params)
	charge = 0.0
	charge_changed.emit(0.0)
	_cooldown_left = cooldown


func _eased(c: float) -> float:
	# Quick start so taps still give a useful small ball.
	return BlastParams.MIN_CHARGE + (1.0 - BlastParams.MIN_CHARGE) * ease(c, 0.8)


func _input_allowed() -> bool:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	return captured or not Input.get_connected_joypads().is_empty()


func _update_visual(delta: float) -> void:
	_wobble += delta * (6.0 + charge * 14.0)
	if charging:
		var r := BlastParams.from_charge(_eased(charge)).ball_radius
		var pulse := 1.0 + sin(_wobble) * 0.06 * charge
		_ball.visible = true
		_ball.scale = Vector3.ONE * r * 2.0 * pulse
		# Bigger balls sit further from the camera so they stay in frame.
		_ball.position = Vector3(0, 0, -r * 1.2)
		_light.light_energy = 0.6 + charge * 2.5
		_light.omni_range = 1.5 + charge * 3.0
	else:
		_ball.visible = false
		_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 12.0)
