class_name Player
extends CharacterBody3D
## First-person controller (mouse + keyboard, gamepad, touch). The fire
## button shoots a projectile along where you look.

## A shot leaves from `from` (your eye) along `direction`.
signal fired(from: Vector3, direction: Vector3)

const COOLDOWN := 0.3  ## seconds between two shots
const FOV := 80.0
const KILL_Y := -25.0
## Loose pieces lighter than this (kg) are shoved aside when you walk into
## them; heavier ones are obstacles.
const SHOVE_MASS := 500.0
const SHOVE_SPEED := 1.6  ## m/s
## Rubble up to this high (m) is stepped onto instead of stopping you.
const STEP := 0.6
const EYES := 1.6  ## m above your feet

@export var walk_speed := 6.5
@export var sprint_speed := 10.0
@export var acceleration := 60.0
@export var air_acceleration := 18.0
@export var jump_velocity := 7.0
@export var mouse_sensitivity := 0.0022
@export var stick_sensitivity := 3.2  ## radians per second at full tilt

var input_enabled := true
## Set by TouchControls: stick vector (x right, y back), jump and fire taps.
var touch_move := Vector2.ZERO
var touch_jump := false
var touch_fire := false
var cooldown_left := 0.0
var head: Node3D
var camera: Camera3D
## Set by the world, to shove loose pieces aside.
var pieces: Pieces

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn: Transform3D
var _lift := 0.0  # the eyes lag behind a step up, so the view does not jump


func _init() -> void:
	collision_layer = Structure.LAYER_PLAYER
	collision_mask = Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS
	floor_snap_length = 0.3
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	head = Node3D.new()
	head.position.y = EYES
	add_child(head)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 400.0
	camera.current = true
	head.add_child(camera)


func _ready() -> void:
	add_to_group("player")
	_spawn = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		look(Vector2(-motion.relative.x, -motion.relative.y) * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		# A real mouse takes the pointer first, then its clicks fire; a tap
		# turned into a click (emulation) does neither: touch has its button.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("fire"):
			fire()
	elif event.is_action_pressed("fire"):
		fire()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func look(delta_angles: Vector2) -> void:
	rotate_y(delta_angles.x)
	head.rotation.x = clampf(head.rotation.x + delta_angles.y, -1.5, 1.5)


## Shoots if the last shot is far enough behind.
func fire() -> bool:
	if cooldown_left > 0.0:
		return false
	cooldown_left = COOLDOWN
	fired.emit(camera.global_position, -camera.global_basis.z)
	return true


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	var stick := Vector2.ZERO
	var move := Vector2.ZERO
	if input_enabled:
		stick = Input.get_vector("look_right", "look_left", "look_down", "look_up")
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		move = (move + touch_move).limit_length(1.0)
		if touch_fire:
			fire()
	touch_fire = false
	if stick != Vector2.ZERO:
		# Squared response curve gives fine aim near the centre.
		look(stick * stick.length() * stick_sensitivity * delta)

	var wish := (transform.basis * Vector3(move.x, 0, move.y)).limit_length(1.0)
	var speed := sprint_speed if input_enabled and Input.is_action_pressed("sprint") else walk_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector3(velocity.x, 0, velocity.z).move_toward(wish * speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		if input_enabled and (Input.is_action_just_pressed("jump") or touch_jump):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta
	touch_jump = false
	move_and_slide()
	_climb(wish, delta)
	_lift = move_toward(_lift, 0.0, delta * 3.0)
	head.position.y = EYES - _lift
	_shove()
	if global_position.y < KILL_Y:
		global_transform = _spawn
		velocity = Vector3.ZERO


## Stopped by something low while walking: step up onto it.
func _climb(wish: Vector3, delta: float) -> void:
	if not is_on_floor() or wish.length() < 0.2:
		return
	var blocked := false
	for k in get_slide_collision_count():
		var n := get_slide_collision(k).get_normal()
		if absf(n.y) < 0.5 and n.dot(wish) < -0.3:
			blocked = true
	if not blocked:
		return
	var ahead := wish.normalized() * maxf(walk_speed * delta, 0.15)
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP):
		return  # no headroom
	xf.origin.y += STEP
	if test_move(xf, ahead):
		return  # too high to step onto
	xf.origin += ahead
	var landing := KinematicCollision3D.new()
	if not test_move(xf, Vector3.DOWN * STEP, landing) or landing.get_normal().y < 0.6:
		return  # nothing flat enough up there
	var to := xf.origin + landing.get_travel()
	var rise := to.y - global_position.y
	if rise < 0.03:
		return
	global_position = to
	_lift = minf(_lift + rise, STEP)


## Light pieces you walk into are nudged aside (never launched).
func _shove() -> void:
	if pieces == null:
		return
	for k in get_slide_collision_count():
		var c := get_slide_collision(k)
		var i := pieces.index_of(c.get_collider_rid())
		if i < 0 or pieces.mass[i] > SHOVE_MASS:
			continue
		var way := -c.get_normal()
		way.y = 0.0
		if way.length() < 0.3:
			continue  # standing on it
		way = way.normalized()
		var lack := SHOVE_SPEED - pieces.velocity_of(i).dot(way)
		if lack > 0.0:
			pieces.push(i, way * minf(lack, 0.5))
