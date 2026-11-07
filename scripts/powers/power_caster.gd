class_name PowerCaster
extends Node3D
## The player's two powers. Cast (click, RT, violet button) opens a black
## hole where you aim. Shield (right click, E, LT/LB/RB, its touch slot)
## raises a curved shell of black ice around your front at once. Each power
## has its own cooldown. A faint marker shows where the black hole would land.

signal cast(power: int)
signal denied(power: int)

const MARK_ALPHA := 0.28

var selected := PowerDefs.Power.VORTEX
## Seconds left before each power can be cast again.
var cooldown_left := [0.0, 0.0]
var auto_input := false  ## true when a script (demo, tests) drives the caster
var touch_held := false  ## set by TouchControls while the cast button is held
## Set by TouchControls on finger down: a tap shorter than a frame still casts.
var touch_tapped := false
var enabled := true
## Where the selected power would land.
var target := Vector3.ZERO

var _was_held := false
var _mouse_armed := false
var _mark: MeshInstance3D
var _mark_mat: StandardMaterial3D


func _ready() -> void:
	_build_mark.call_deferred()


func _process(delta: float) -> void:
	for k in 2:
		if cooldown_left[k] > 0.0:
			cooldown_left[k] = maxf(cooldown_left[k] - delta, 0.0)
			if cooldown_left[k] == 0.0:
				Sfx.ui("ready", -18.0, 1.0 + k * 0.12)
	if not auto_input:
		_read_input()
	_update_aim()
	_update_mark()


func _player() -> Player:
	var world := GameWorld.of(self)
	return world.player if world else null


func _read_input() -> void:
	var player := _player()
	if player and not player.input_enabled:
		_was_held = false
		touch_tapped = false
		return
	if Input.is_action_just_pressed("shield") and _pointer_ready():
		cast_power(PowerDefs.Power.SHIELD)
	# The click that grabs the mouse (or resumes) must not also cast: the
	# mouse button only counts once it has been up with the pointer held.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var mouse_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not captured:
		_mouse_armed = false
	elif not mouse_down:
		_mouse_armed = true
	var pressed := Input.is_action_pressed("cast") and _pointer_ready()
	if mouse_down and not _mouse_armed:
		pressed = false
	var held := touch_held or pressed
	if (held or touch_tapped) and not _was_held:
		cast_selected()
	touch_tapped = false
	_was_held = held


## Gamepad aiming works without the mouse; the mouse needs to be captured.
func _pointer_ready() -> bool:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	return captured or not Input.get_connected_joypads().is_empty()


## Picks the power the cast button fires. The shield goes up right away
## instead: it is never the selected power.
func select(power: int) -> void:
	if power == PowerDefs.Power.SHIELD:
		cast_power(power)
		return
	if power == selected:
		return
	selected = power
	Sfx.ui("select", -10.0, 0.9 + power * 0.1)


func is_ready(power: int) -> bool:
	return cooldown_left[power] <= 0.0


func cooldown_fraction(power: int) -> float:
	return cooldown_left[power] / PowerDefs.cooldown(power)


## Casts the selected power now if it is ready.
func cast_selected() -> bool:
	return cast_power(selected)


## Casts `power` now if it is ready.
func cast_power(power: int) -> bool:
	if not enabled:
		return false
	if not is_ready(power):
		denied.emit(power)
		Sfx.ui("denied", -8.0)
		return false
	var world := GameWorld.of(self)
	if world == null:
		return false
	_update_aim()
	match power:
		PowerDefs.Power.VORTEX:
			world.cast_vortex(target)
		PowerDefs.Power.SHIELD:
			world.cast_shield(shield_base())
	cooldown_left[power] = PowerDefs.cooldown(power)
	cast.emit(power)
	return true


## Selects (unless it is the shield) and casts `power` (scripts, tests).
func cast_now(power: int) -> bool:
	if power != PowerDefs.Power.SHIELD:
		selected = power
	return cast_power(power)


# --- Aiming --------------------------------------------------------------------


func _update_aim() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * PowerDefs.RANGE)
	q.collision_mask = (
		DebrisSystem.LAYER_WORLD
		| DebrisSystem.LAYER_STRUCTURES
		| DebrisSystem.LAYER_DEBRIS
		| DebrisSystem.LAYER_RUBBLE
	)
	# Aim through yourself and your own shields.
	var skip: Array[RID] = []
	var player := _player()
	if player:
		skip.append(player.get_rid())
	for shield in get_tree().get_nodes_in_group("ice_shield"):
		skip.append((shield as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		target = from + dir * 30.0
		return
	# Open just off the surface so the core is visible.
	target = (hit["position"] as Vector3) - dir * 1.0


## Where the shield rises: around you, curving across the way you look.
## You never place it yourself.
func shield_base() -> Transform3D:
	var cam := get_viewport().get_camera_3d()
	var player := _player()
	var origin := player.global_position if player else global_position
	var fwd := -cam.global_basis.z if cam else -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	# Centred on the player's feet, facing where they look.
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), origin)


# --- Marker ---------------------------------------------------------------------


func _build_mark() -> void:
	var world := GameWorld.of(self)
	if world == null:
		return
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.albedo_color = Color(Palette.VIOLET, MARK_ALPHA)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.97
	ring.outer_radius = 1.0
	ring.rings = 64
	ring.ring_segments = 4
	_mark = MeshInstance3D.new()
	_mark.name = "PowerMark"
	_mark.mesh = ring
	_mark.material_override = _mark_mat
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_mark)


func _update_mark() -> void:
	if _mark == null:
		return
	var player := _player()
	_mark.visible = selected != PowerDefs.Power.SHIELD and player != null and player.input_enabled
	if not _mark.visible:
		return
	var r := PowerDefs.VORTEX_RADIUS
	_mark.global_position = target + Vector3(0, 0.05, 0)
	_mark.scale = Vector3(r, 1, r)
	_mark_mat.albedo_color.a = MARK_ALPHA if is_ready(selected) else MARK_ALPHA * 0.35
