class_name Player
extends CharacterBody3D
## First-person controller (mouse + keyboard, gamepad, touch) with health.
## Heavy debris, stones, falling pieces, your own blasts and hard landings
## hurt; health comes back after a few seconds without being hit.

signal damaged(amount: float, from: Vector3)
signal died

const MAX_HEALTH := 100.0
const REGEN_DELAY := 3.0
const REGEN_RATE := 14.0  ## health per second
const SAFE_FALL_SPEED := 11.0  ## m/s landing speed before falls hurt
const FALL_DAMAGE := 10.0  ## per m/s above the safe speed
const PUSH_MAX_SPEED := 2.0  ## m/s, debris you walk into
const KILL_Y := -25.0

@export var walk_speed := 7.0
@export var sprint_speed := 11.0
@export var acceleration := 60.0
@export var air_acceleration := 18.0
@export var jump_velocity := 7.5
@export var mouse_sensitivity := 0.0022
@export var stick_sensitivity := 3.2  ## radians per second at full tilt
@export var push_strength := 2.5  ## how hard walking shoves debris

## Velocity from blasts; decays separately so the player can be flung.
var external_velocity := Vector3.ZERO
var input_enabled := true
## Set by TouchControls: stick vector (x right, y back) and a jump request.
var touch_move := Vector2.ZERO
var touch_jump := false
var health := MAX_HEALTH
var dead := false
## Tests and the sandbox can switch damage off.
var invulnerable := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn: Transform3D
var _since_hit := 99.0
var _air_speed := 0.0
var _was_on_floor := true
var _hit_from := {}  # rid -> time, so one body hurts once per contact
var _clock := 0.0
var _probe := PhysicsShapeQueryParameters3D.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var power: PowerCaster = $Head/Camera3D/Power


func _ready() -> void:
	_spawn = global_transform
	add_to_group("player")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.55
	capsule.height = 2.0
	_probe.shape = capsule
	_probe.collision_mask = DebrisSystem.LAYER_DEBRIS
	_probe.exclude = [get_rid()]


func reset_spawn() -> void:
	_spawn = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		look(Vector2(-motion.relative.x, -motion.relative.y) * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not TouchControls.should_show():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func look(delta_angles: Vector2) -> void:
	rotate_y(delta_angles.x)
	head.rotation.x = clampf(head.rotation.x + delta_angles.y, -1.5, 1.5)


func add_impulse(v: Vector3) -> void:
	external_velocity += v


func _physics_process(delta: float) -> void:
	_clock += delta
	_since_hit += delta
	if not dead and _since_hit > REGEN_DELAY and health < MAX_HEALTH:
		health = minf(health + REGEN_RATE * delta, MAX_HEALTH)
	var stick := Vector2.ZERO
	var move := Vector2.ZERO
	if input_enabled:
		stick = Input.get_vector("look_right", "look_left", "look_down", "look_up")
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		move = (move + touch_move).limit_length(1.0)
	if stick != Vector2.ZERO:
		# Squared response curve gives fine aim near the centre.
		look(stick * stick.length() * stick_sensitivity * delta)

	var wish := (transform.basis * Vector3(move.x, 0, move.y)).limit_length(1.0)
	var speed := sprint_speed if input_enabled and Input.is_action_pressed("sprint") else walk_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var target := wish * speed
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		if input_enabled and (Input.is_action_just_pressed("jump") or touch_jump):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta

	touch_jump = false

	# Blast velocity is added on top and bleeds off quickly on the ground.
	velocity += external_velocity
	_air_speed = maxf(-velocity.y, 0.0)
	move_and_slide()
	if is_on_floor() and not _was_on_floor and _air_speed > SAFE_FALL_SPEED:
		hurt((_air_speed - SAFE_FALL_SPEED) * FALL_DAMAGE, global_position + Vector3.DOWN)
	_was_on_floor = is_on_floor()
	velocity -= external_velocity
	var drag := 6.0 if is_on_floor() else 1.2
	external_velocity = external_velocity.move_toward(
		Vector3.ZERO, drag * delta * maxf(external_velocity.length(), 4.0)
	)
	if is_on_floor() and external_velocity.y < 0.0:
		external_velocity.y = 0.0

	_push_debris()
	_check_hazards()
	if global_position.y < KILL_Y:
		hurt(MAX_HEALTH * 2.0, global_position)


func respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	external_velocity = Vector3.ZERO
	health = MAX_HEALTH
	dead = false


## Loses `amount` health. `from` is where the hit came from (for feedback).
func hurt(amount: float, from: Vector3) -> void:
	if dead or invulnerable or amount <= 0.5:
		return
	health -= amount
	_since_hit = 0.0
	damaged.emit(amount, from)
	if health <= 0.0:
		health = 0.0
		dead = true
		input_enabled = false
		died.emit()


## Anything heavy moving into the player hurts, by momentum.
func _check_hazards() -> void:
	var world := GameWorld.of(self)
	if world == null or dead:
		return
	_probe.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0))
	var hits := get_world_3d().direct_space_state.intersect_shape(_probe, 16)
	for h in hits:
		var rid: RID = h["rid"]
		if _clock - float(_hit_from.get(rid, -10.0)) < 0.5:
			continue
		var motion := Hazards.motion_of(world, rid, h["collider"])
		if motion.is_empty():
			continue
		var v: Vector3 = motion["velocity"]
		# Only the piece's own motion toward you counts: walking, running
		# or landing on debris never hurts (hard landings are fall damage).
		var closing := v.length()
		var src := _body_position(world, rid, h["collider"])
		if src != Vector3.INF:
			var to_me := global_position + Vector3(0, 0.9, 0) - src
			if to_me.length() > 0.01:
				closing = maxf(v.dot(to_me.normalized()), 0.0)
		var dmg := Hazards.damage_for(float(motion["mass"]), closing)
		if dmg > 0.0:
			_hit_from[rid] = _clock
			hurt(dmg, global_position - v.normalized())


func _push_debris() -> void:
	var world := GameWorld.of(self)
	if world == null:
		return
	for k in get_slide_collision_count():
		var c := get_slide_collision(k)
		var idx := world.debris.index_of(c.get_collider_rid())
		if idx >= 0:
			var push := -c.get_normal() * push_strength
			push.y = maxf(push.y, 0.0)
			var v := world.debris.velocity_of(idx) + push * 0.2
			# Nudged aside, never launched: pushing every frame must not build
			# up speed (a launched piece could bounce back and hurt).
			var flat := Vector2(v.x, v.z).limit_length(PUSH_MAX_SPEED)
			world.debris.set_velocity(idx, Vector3(flat.x, v.y, flat.y))


func _body_position(world: GameWorld, rid: RID, collider: Object) -> Vector3:
	if collider is Node3D:
		return (collider as Node3D).global_position
	var i := world.debris.index_of(rid)
	return world.debris.position_of(i) if i >= 0 else Vector3.INF
