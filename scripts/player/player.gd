class_name Player
extends CharacterBody3D
## First-person controller: mouse + keyboard and gamepad.

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
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn: Transform3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var power: PowerHand = $Head/Camera3D/PowerHand


func _ready() -> void:
	_spawn = global_transform
	add_to_group("player")


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
	move_and_slide()
	velocity -= external_velocity
	var drag := 6.0 if is_on_floor() else 1.2
	external_velocity = external_velocity.move_toward(
		Vector3.ZERO, drag * delta * maxf(external_velocity.length(), 4.0)
	)
	if is_on_floor() and external_velocity.y < 0.0:
		external_velocity.y = 0.0

	_push_debris()
	if global_position.y < -30.0:
		respawn()


func respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	external_velocity = Vector3.ZERO


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
			world.debris.set_velocity(idx, world.debris.velocity_of(idx) + push * 0.2)
