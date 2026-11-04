class_name PowerCaster
extends Node3D
## The player's three powers. Pick one (1/2/3, wheel, LB/RB, touch), hold the
## cast button to grow it through three sizes while a preview shows where and
## how big, release to cast. Each power and size has its own cooldown.

signal selection_changed(power: int)
signal tier_changed(tier: int)
signal cast(power: int, tier: int)
signal denied(power: int)

const PREVIEW_ALPHA := 0.22

var selected := PowerDefs.Power.GRAVITY
var holding := false
var held_time := 0.0
var tier := 0
## Seconds left before each power can be cast again.
var cooldown_left := [0.0, 0.0, 0.0]
var cooldown_total := [1.0, 1.0, 1.0]
var auto_input := false  ## true when a script (demo, tests) drives the caster
var touch_held := false  ## set by TouchControls while the cast button is held
var enabled := true
## Where the current power would land (updated while holding).
var target := Vector3.ZERO
var target_valid := false

var _preview: Node3D
var _preview_sphere: MeshInstance3D
var _preview_ring: MeshInstance3D
var _preview_box: MeshInstance3D
var _preview_mat: StandardMaterial3D
var _hand: MeshInstance3D
var _hand_light: OmniLight3D
var _wobble := 0.0


func _ready() -> void:
	_build_hand()
	_build_preview.call_deferred()


func _process(delta: float) -> void:
	for k in 3:
		if cooldown_left[k] > 0.0:
			cooldown_left[k] = maxf(cooldown_left[k] - delta, 0.0)
			if cooldown_left[k] == 0.0:
				Sfx.ui("ready", -18.0, 1.0 + k * 0.12)
	if not auto_input:
		_read_input()
	if holding:
		held_time += delta
		var t := PowerDefs.tier_for(held_time)
		if t != tier:
			tier = t
			tier_changed.emit(tier)
			Sfx.ui("tier", -10.0, 1.0 + tier * 0.25)
			Sfx.update_charge(tier / 2.0)
	_update_aim()
	_update_visuals(delta)


func _read_input() -> void:
	var player := get_parent_node_3d()
	while player and not player is Player:
		player = player.get_parent_node_3d()
	if player and not (player as Player).input_enabled:
		if holding:
			cancel()
		return
	if Input.is_action_just_pressed("power_1"):
		select(PowerDefs.Power.GRAVITY)
	elif Input.is_action_just_pressed("power_2"):
		select(PowerDefs.Power.PORTAL)
	elif Input.is_action_just_pressed("power_3"):
		select(PowerDefs.Power.SHIELD)
	elif Input.is_action_just_pressed("power_next"):
		select((selected + 1) % 3)
	elif Input.is_action_just_pressed("power_prev"):
		select((selected + 2) % 3)
	var held := touch_held or (Input.is_action_pressed("cast") and _pointer_ready())
	if held and not holding:
		begin()
	elif not held and holding:
		release()


func _pointer_ready() -> bool:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	return captured or not Input.get_connected_joypads().is_empty()


func select(power: int) -> void:
	if power == selected:
		return
	if holding:
		cancel()
	selected = power
	selection_changed.emit(selected)
	Sfx.ui("select", -10.0, 0.9 + power * 0.1)


func is_ready(power: int) -> bool:
	return cooldown_left[power] <= 0.0


func begin() -> void:
	if not enabled:
		return
	if not is_ready(selected):
		denied.emit(selected)
		Sfx.ui("denied", -8.0)
		return
	holding = true
	held_time = 0.0
	tier = 0
	tier_changed.emit(tier)
	Sfx.start_charge()
	Sfx.update_charge(0.0)


func cancel() -> void:
	holding = false
	held_time = 0.0
	tier = 0
	Sfx.stop_charge()


func release() -> void:
	if not holding:
		return
	holding = false
	Sfx.stop_charge()
	_update_aim()
	var world := GameWorld.of(self)
	if world == null or not enabled:
		cancel()
		return
	match selected:
		PowerDefs.Power.GRAVITY:
			world.cast_gravity(target, tier)
		PowerDefs.Power.PORTAL:
			world.cast_portal(target, tier)
		PowerDefs.Power.SHIELD:
			world.cast_shield(_shield_base(), tier)
	var cd := PowerDefs.cooldown(selected, tier)
	cooldown_left[selected] = cd
	cooldown_total[selected] = cd
	cast.emit(selected, tier)
	held_time = 0.0


## Casts right away at a given size, ignoring how long the button was held.
func cast_now(power: int, size_tier: int) -> void:
	selected = power
	holding = true
	held_time = 0.0
	tier = size_tier
	release()


# --- Aiming --------------------------------------------------------------------


func _update_aim() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * PowerDefs.RANGE)
	q.collision_mask = DebrisSystem.LAYER_WORLD | DebrisSystem.LAYER_STRUCTURES | DebrisSystem.LAYER_DEBRIS
	var player := GameWorld.of(self).player if GameWorld.of(self) else null
	# Aim through your own shields: they are made to stand in front of you.
	var skip: Array[RID] = []
	if player:
		skip.append(player.get_rid())
	for shield in get_tree().get_nodes_in_group("ice_shield"):
		skip.append((shield as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	target_valid = not hit.is_empty()
	match selected:
		PowerDefs.Power.GRAVITY:
			if hit.is_empty():
				target = from + dir * 30.0
			else:
				# Sit just in front of the surface so the orb is visible.
				var p := PowerDefs.gravity_params(tier)
				target = (hit["position"] as Vector3) - dir * minf(p.ball_radius * 2.0, 1.0)
		PowerDefs.Power.PORTAL:
			if hit.is_empty():
				# Aiming at the sky: drop it at range on the ground ahead.
				var flat := Vector3(dir.x, 0, dir.z).normalized()
				target = Vector3(from.x, 0, from.z) + flat * 40.0
			else:
				target = hit["position"]
		PowerDefs.Power.SHIELD:
			target = _shield_base().origin


func _shield_base() -> Transform3D:
	var cam := get_viewport().get_camera_3d()
	var player := GameWorld.of(self).player if GameWorld.of(self) else null
	var origin := player.global_position if player else global_position
	var fwd := -cam.global_basis.z if cam else -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var at := origin + fwd * PowerDefs.SHIELD_DISTANCE
	at.y = origin.y
	# Face the player: local -Z points away from them.
	var basis := Basis.looking_at(fwd, Vector3.UP)
	return Transform3D(basis, at)


# --- Visuals -------------------------------------------------------------------


func _build_hand() -> void:
	_hand = MeshInstance3D.new()
	_hand.mesh = SphereMesh.new()
	(_hand.mesh as SphereMesh).radius = 0.5
	(_hand.mesh as SphereMesh).height = 1.0
	_hand.material_override = preload("res://materials/power.tres")
	_hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand.visible = false
	add_child(_hand)
	_hand_light = OmniLight3D.new()
	_hand_light.light_color = Palette.VIOLET
	_hand_light.light_energy = 0.0
	add_child(_hand_light)


func _build_preview() -> void:
	var world := GameWorld.of(self)
	if world == null:
		return
	_preview = Node3D.new()
	_preview.name = "PowerPreview"
	world.add_child(_preview)
	_preview_mat = StandardMaterial3D.new()
	_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_mat.albedo_color = Color(Palette.VIOLET, PREVIEW_ALPHA)
	_preview_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview_mat.no_depth_test = false
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_preview_sphere = _mesh(sphere)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.95
	ring.outer_radius = 1.0
	ring.rings = 64
	_preview_ring = _mesh(ring)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_preview_box = _mesh(box)
	_preview.visible = false


func _mesh(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _preview_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.add_child(mi)
	return mi


func _update_visuals(delta: float) -> void:
	_wobble += delta * (6.0 + tier * 6.0)
	var k := float(tier) / 2.0
	_hand.visible = holding
	if holding:
		var r := lerpf(0.022, 0.055, k) * (1.0 + sin(_wobble) * 0.05)
		_hand.scale = Vector3.ONE * r * 2.0
		_hand.position = Vector3(0, 0, -r * 0.5)
		_hand_light.light_energy = 0.8 + k * 2.0
	else:
		_hand_light.light_energy = move_toward(_hand_light.light_energy, 0.0, delta * 10.0)
	if _preview == null:
		return
	_preview.visible = holding
	if not holding:
		return
	_preview_sphere.visible = selected == PowerDefs.Power.GRAVITY
	_preview_ring.visible = selected != PowerDefs.Power.SHIELD
	_preview_box.visible = selected == PowerDefs.Power.SHIELD
	_preview_mat.albedo_color.a = PREVIEW_ALPHA + 0.08 * sin(_wobble)
	match selected:
		PowerDefs.Power.GRAVITY:
			var p := PowerDefs.gravity_params(tier)
			_preview_sphere.global_position = target
			_preview_sphere.scale = Vector3.ONE * p.break_radius
			_preview_ring.global_position = target
			_preview_ring.scale = Vector3.ONE * p.radius
		PowerDefs.Power.PORTAL:
			var r: float = PowerDefs.PORTAL_RADIUS[tier]
			_preview_ring.global_position = target + Vector3(0, 0.05, 0)
			_preview_ring.scale = Vector3(r, 1, r)
		PowerDefs.Power.SHIELD:
			var base := _shield_base()
			var w: float = PowerDefs.SHIELD_WIDTH[tier]
			var h: float = PowerDefs.SHIELD_HEIGHT[tier]
			_preview_box.global_transform = base.translated_local(Vector3(0, h * 0.5, 0))
			_preview_box.scale = Vector3(w, h, IceShield.THICKNESS)
