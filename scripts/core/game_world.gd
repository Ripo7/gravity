class_name GameWorld
extends Node3D
## Root of a playable arena: wires structures, debris, player, blasts, juice.

signal detonated(at: Vector3, params: BlastParams)

const SLOWMO_SCALE := 0.25  ## time scale for a full-charge blast
const SLOWMO_HOLD := 0.45  ## real seconds at full slow-down
const SLOWMO_RECOVER := 0.7  ## real seconds to ease back to 1x

@export var structures: StructureSet
@export var debris: DebrisSystem
@export var player: Player
@export var structure_root: Node3D

var blasts_total := 0
var _slowmo_left := 0.0
var _slowmo_total := 0.0
var _slowmo_scale := SLOWMO_SCALE


static func of(node: Node) -> GameWorld:
	var n := node
	while n:
		if n is GameWorld:
			return n
		n = n.get_parent()
	return null


func _ready() -> void:
	Engine.time_scale = 1.0
	if OS.has_feature("web_ios") or OS.has_feature("web_android"):
		# Phones have 3x screens: render 3D at lower resolution, keep UI sharp.
		get_viewport().scaling_3d_scale = 0.6
	build_structures()


func build_structures() -> void:
	var root: Node = structure_root if structure_root else self
	for s in root.get_children():
		if s is Structure:
			var st := s as Structure
			structures.add_structure(st.global_transform, st.build_segments())


func detonate(at: Vector3, params: BlastParams) -> GravityBlast:
	blasts_total += 1
	var blast := GravityBlast.new()
	blast.setup(self, params, at)
	add_child(blast)
	var fx := BlastFx.new()
	fx.setup(params, at, blast)
	add_child(fx)
	var cam := get_viewport().get_camera_3d() as CameraShake
	if cam:
		var d := cam.global_position.distance_to(at)
		var near := clampf(1.0 - d / (params.radius * 4.0), 0.15, 1.0)
		cam.add_trauma(params.shake * 0.35 * near)
		blast.burst.connect(
			func() -> void:
				cam.add_trauma(params.shake * 0.8 * near)
				cam.kick_fov(4.0 + 8.0 * params.charge * near)
		)
	if params.slow_motion:
		# Full charge: deep slow-down. Medium charge: a lighter one.
		var depth := remap(params.charge, 0.6, 1.0, 0.5, SLOWMO_SCALE)
		blast.burst.connect(slow_motion.bind(depth))
	detonated.emit(at, params)
	return blast


func slow_motion(scale := SLOWMO_SCALE) -> void:
	_slowmo_scale = scale
	_slowmo_total = SLOWMO_HOLD + SLOWMO_RECOVER
	_slowmo_left = _slowmo_total


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_arena"):
		reset()
	if _slowmo_left > 0.0:
		var real := delta / maxf(Engine.time_scale, 0.001)
		_slowmo_left = maxf(_slowmo_left - real, 0.0)
		var elapsed := _slowmo_total - _slowmo_left
		if elapsed < SLOWMO_HOLD:
			Engine.time_scale = _slowmo_scale
		else:
			var k := (elapsed - SLOWMO_HOLD) / SLOWMO_RECOVER
			Engine.time_scale = lerpf(_slowmo_scale, 1.0, ease(clampf(k, 0.0, 1.0), 0.5))
		if _slowmo_left <= 0.0:
			Engine.time_scale = 1.0


func reset() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()
