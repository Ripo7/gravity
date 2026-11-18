class_name Player
extends CharacterBody3D
## The brute, as you steer it: a third-person controller (mouse + keyboard,
## gamepad, touch). You look around with the camera, which sits behind the
## character's left shoulder; the character goes where you push, relative to
## the camera, and turns to face where it goes. The punch button throws a
## blow, then the next of the combination if it is pressed again, and so on;
## there is a kick too. While such a move plays, the body goes where the
## move steps (Character.root_motion).
##
## What a blow does to what it reaches is not decided here: when a fist or
## a foot gets there, the brute says where it went and how hard (`blow`),
## and whoever stands there takes it.

## A fist or a foot gets there: it went from `from` (in the body, at its
## height) to `to`, `power` hard (2 a blow, 3 a heavy one).
signal blow(from: Vector3, to: Vector3, power: int)

const FOV := 70.0
## Something up to this high (m) is stepped onto instead of stopping you.
const STEP := 0.6
## The camera turns about a point this high above the feet (m), and sits
## SHOULDER to the left of it (SIDE -1), BACK behind and RAISED above, less
## when something is in the way: ROOM is kept between it and that.
const HEAD := 1.5
const SHOULDER := 0.6
const SIDE := -1.0
const BACK := 3.2
const RAISED := 0.2
const ROOM := 0.2
## With less room than this behind its shoulder (m), the camera goes
## behind its head instead.
const TIGHT := 1.4
## Pushed in closer than this (m), the camera would see nothing but the
## character's back: the character is not drawn.
const TOO_CLOSE := 0.7
const LOOK_DOWN := -1.2  ## rad
const LOOK_UP := 1.0
## The camera comes back out at this speed (m/s) once the way is clear; it
## goes in at once.
const EASE_OUT := 6.0
## The character turns to where it goes at this rate (rad/s).
const TURN := 12.0
## In the air this long (s) without having jumped: it is a fall.
const FALL_AFTER := 0.12
## A blow reaches this much farther than the wrist (m): the fist.
const FIST := 0.1

## Full tilt of the stick, or the keys: a jog. The clips' feet do not slide
## at these speeds (see Character).
@export var run_speed := Character.JOG_PACE
@export var sprint_speed := Character.SPRINT_PACE
@export var acceleration := 30.0
@export var air_acceleration := 12.0
@export var jump_velocity := 6.0
@export var mouse_sensitivity := 0.0022
@export var stick_sensitivity := 3.2  ## radians per second at full tilt

## Set by TouchControls and scripted runs: stick vector (x right, y back),
## and taps.
var touch_move := Vector2.ZERO
var touch_jump := false
var touch_punch := false
var touch_kick := false
## Set by TouchControls and scripted runs: sprint without the key.
var touch_sprint := false
## Where the camera looks (rad): `yaw` about the vertical (0 is along -Z),
## `pitch` up (positive) or down.
var yaw := 0.0
var pitch := -0.15
## Where the character faces (rad, like `yaw`).
var facing := 0.0
var camera: Camera3D
var character: Character

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _lift := 0.0  # the view and the body lag behind a step up, so they do not jump
var _pivot: Node3D  # turns with `yaw`, at head height
var _arm: Node3D  # tilts with `pitch`
var _shoulder := SHOULDER
var _back := BACK
var _airborne := 0.0  # s since the feet left the ground
var _fell := 0.0  # m/s down, just before landing
var _wish := Vector3.ZERO  # where the stick pushes, in the world
var _punch_to := 0.0  # where the strike under way is thrown (rad, like `facing`)
var _sight := PhysicsRayQueryParameters3D.new()  # what the camera stays in front of


func _init() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.STRUCTURE | Layers.RUBBLE
	floor_snap_length = 0.3
	# A block that goes off under its feet does not take it along.
	platform_floor_layers = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	character = Character.new()
	add_child(character)
	_pivot = Node3D.new()
	_pivot.position.y = HEAD
	add_child(_pivot)
	_arm = Node3D.new()
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 400.0
	camera.current = true
	_arm.add_child(camera)
	# The camera stays in front of what stands, not of what lies about.
	_sight.collision_mask = Layers.WORLD | Layers.STRUCTURE
	character.swung.connect(_on_swung)
	character.struck.connect(_on_struck)
	_pose_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		look(Vector2(-motion.relative.x, -motion.relative.y) * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		# A real mouse takes the pointer first, then its clicks strike; a tap
		# turned into a click (emulation) does neither: touch has its button.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("punch"):
			punch()
		elif event.is_action_pressed("kick"):
			kick()
	elif event.is_action_pressed("punch"):
		punch()
	elif event.is_action_pressed("kick"):
		kick()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Turns the camera: x to the left, y up (rad).
func look(delta_angles: Vector2) -> void:
	yaw = wrapf(yaw + delta_angles.x, -PI, PI)
	pitch = clampf(pitch + delta_angles.y, LOOK_DOWN, LOOK_UP)
	_pose_camera()


## Turns the camera so that the middle of the view is on `target`.
func look_at_point(target: Vector3) -> void:
	# The camera is beside the point it turns about, so its line of sight
	# does not go through that point: a few rounds get it onto the target.
	for k in 4:
		var d := target - camera.global_position
		yaw = atan2(-d.x, -d.z)
		pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), LOOK_DOWN, LOOK_UP)
		_pose_camera()


## Throws a blow, or asks for the next of the combination (see
## Character.punch). Returns false if it cannot: only feet on the ground.
func punch() -> bool:
	return is_on_floor() and character.punch()


## A kick, feet on the ground.
func kick() -> bool:
	return is_on_floor() and character.kick()


func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("look_right", "look_left", "look_down", "look_up")
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move = (move + touch_move).limit_length(1.0)
	if touch_punch:
		punch()
	if touch_kick:
		kick()
	touch_punch = false
	touch_kick = false
	if stick != Vector2.ZERO:
		# Squared response curve gives fine aim near the centre.
		look(stick * stick.length() * stick_sensitivity * delta)

	# Where you push, seen from the camera. How far you push sets the pace.
	var wish := (Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)).limit_length(1.0)
	_wish = wish
	var sprinting := touch_sprint or Input.is_action_pressed("sprint")
	var speed := sprint_speed if sprinting else run_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var busy := character.striking()
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if busy:
		# A blow steps as it was made to: the body follows its steps.
		horizontal = character.root_motion() / delta
		horizontal.y = 0.0
	else:
		horizontal = horizontal.move_toward(wish * speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		if not busy and (Input.is_action_just_pressed("jump") or touch_jump):
			velocity.y = jump_velocity
			character.jump()
	else:
		velocity.y -= _gravity * delta
		_fell = maxf(-velocity.y, 0.0)
	touch_jump = false
	move_and_slide()
	# A blow that steps in steps up like any other step.
	_climb(horizontal.limit_length(1.0) if busy else wish, delta)
	_lift = move_toward(_lift, 0.0, delta * 3.0)
	_animate(wish, delta)
	_pose_camera(delta)


## Turns the character and tells it what its legs are doing.
func _animate(wish: Vector3, delta: float) -> void:
	if character.striking():
		facing = rotate_toward(facing, _punch_to, TURN * delta)
	elif wish.length() > 0.1:
		facing = rotate_toward(facing, atan2(-wish.x, -wish.z), TURN * delta)
	character.rotation.y = facing
	character.position.y = -_lift
	var along := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if is_on_floor():
		if _airborne > 0.0:
			character.land(_fell, along)
		_airborne = 0.0
		_fell = 0.0
		character.move(along)
	else:
		_airborne += delta
		if _airborne > FALL_AFTER:
			character.fall()


## A strike starts: it is thrown where the stick pushes, or where the
## character faces.
func _on_swung(_move: String) -> void:
	_punch_to = atan2(-_wish.x, -_wish.z) if _wish.length() > 0.1 else facing


## The fist or the foot of the strike under way gets there.
func _on_struck(_move: String) -> void:
	var ahead := Basis(Vector3.UP, facing) * Vector3.FORWARD
	var from := global_position + Vector3.UP * character.height()
	blow.emit(from, from + ahead * (character.reach() + FIST), character.power())


## How far back the camera can go from `from` along `reach` (as a length
## of the boom, BACK at most).
func _room_behind(space: PhysicsDirectSpaceState3D, from: Vector3, reach: Vector3) -> float:
	var length := Vector2(BACK, RAISED).length()
	var hit := _in_the_way(space, from, from + reach * (length + ROOM))
	if hit.is_empty():
		return BACK
	return maxf(from.distance_to(hit["position"]) - ROOM, 0.0) / length * BACK


## The first thing between `from` and `to` that the camera has to stay in
## front of. Empty if there is nothing.
func _in_the_way(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_sight.from = from
	_sight.to = to
	return space.intersect_ray(_sight)


## Puts the camera behind the shoulder, nearer when something is in
## the way (it goes in at once and eases back out over `delta`).
func _pose_camera(delta := 0.0) -> void:
	_pivot.position.y = HEAD - _lift
	_pivot.rotation.y = yaw
	_arm.rotation.x = pitch
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		var head := _pivot.global_position
		var side := _arm.global_basis.x * SIDE
		var up := _arm.global_basis.y
		var back := _arm.global_basis.z
		# To the shoulder first, then back from there.
		var shoulder := SHOULDER
		var hit := _in_the_way(space, head, head + side * (SHOULDER + ROOM))
		if not hit.is_empty():
			shoulder = maxf(head.distance_to(hit["position"]) - ROOM, 0.0)
		var reach := (back * BACK + up * RAISED).normalized()
		var away := _room_behind(space, head + side * shoulder, reach)
		if away < TIGHT:
			# Hemmed in: straight behind its head instead, if there is more
			# room there.
			var behind := _room_behind(space, head, reach)
			if behind > away:
				away = behind
				shoulder = 0.0
		_shoulder = minf(shoulder, move_toward(_shoulder, shoulder, EASE_OUT * delta))
		_back = minf(away, move_toward(_back, away, EASE_OUT * delta))
	camera.position = Vector3(_shoulder * SIDE, RAISED * _back / BACK, _back)
	character.visible = _back > TOO_CLOSE


## Stopped by something low while going along `wish`: step up onto it, if
## it is no higher than STEP and there is room.
func _climb(wish: Vector3, delta: float) -> void:
	if wish.length() < 0.2 or not is_on_floor():
		return
	var way := wish.normalized()
	var blocked := false
	for k in get_slide_collision_count():
		var n := get_slide_collision(k).get_normal()
		# (Anything it cannot walk up: a face steeper than a floor too.)
		if n.y > -0.5 and n.y < 0.7 and n.dot(way) < -0.3:
			blocked = true
	if not blocked:
		return
	var stride := maxf(run_speed * delta, 0.15)
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP):
		return  # no headroom
	xf.origin.y += STEP
	if test_move(xf, way * stride):
		return  # too high to step onto
	xf.origin += way * stride
	var landing := KinematicCollision3D.new()
	if not test_move(xf, Vector3.DOWN * STEP, landing) or landing.get_normal().y < 0.6:
		return  # nothing flat enough up there
	var to := xf.origin + landing.get_travel()
	var rise := to.y - global_position.y
	if rise < 0.03:
		return
	global_position = to
	_lift = minf(_lift + rise, STEP)
