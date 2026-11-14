class_name Player
extends CharacterBody3D
## Third-person controller (mouse + keyboard, gamepad, touch). You look
## around with the camera, which sits behind the character's left shoulder
## (the side of the arm it shoots with, so the arm is in view);
## the character goes where you push, relative to the camera, and turns to
## face where it goes. The fire button shoots a projectile at what is under
## the crosshair, and the character turns to it. The punch button throws a
## jab, then the next punch of the combination if it is pressed again, and
## so on; there is a kick and a duck too. A strike goes for the opponent in
## front, stepping in if it is a little too far. While such a move plays,
## the body goes where the move steps (Character.root_motion).

## A shot leaves from `from` (the character's chest) along `direction`.
signal fired(from: Vector3, direction: Vector3)

const COOLDOWN := 0.3  ## seconds between two shots
const FOV := 70.0
const KILL_Y := -25.0
## Loose pieces lighter than this (kg) are shoved aside when you walk into
## them; heavier ones are obstacles.
const SHOVE_MASS := 500.0
const SHOVE_SPEED := 1.6  ## m/s
## Rubble up to this high (m) is stepped onto instead of stopping you.
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
## Pushed in closer than this (m), the camera would see nothing but the
## character's back: the character is not drawn.
const TOO_CLOSE := 0.7
const LOOK_DOWN := -1.2  ## rad
const LOOK_UP := 1.0
## The camera comes back out at this speed (m/s) once the way is clear; it
## goes in at once.
const EASE_OUT := 6.0
const CHEST := 1.4  ## m above the feet: where a shot leaves from
## The character turns to where it goes at this rate (rad/s), and stays
## turned to where it shot for AIM_HOLD s.
const TURN := 12.0
const AIM_HOLD := 0.45
## In the air this long (s) without having jumped: it is a fall.
const FALL_AFTER := 0.12
## A strike goes for the nearest other brute within SEEK m, if it is less
## than CONE rad off where it is thrown (see Fighter for what it does).
const SEEK := 2.4
const CONE := 1.2

## Full tilt of the stick, or the keys: a jog. The clips' feet do not slide
## at these speeds (see Character).
@export var run_speed := Character.JOG_PACE
@export var sprint_speed := Character.SPRINT_PACE
@export var acceleration := 30.0
@export var air_acceleration := 12.0
@export var jump_velocity := 6.0
@export var mouse_sensitivity := 0.0022
@export var stick_sensitivity := 3.2  ## radians per second at full tilt

var input_enabled := true
## Set by TouchControls: stick vector (x right, y back), jump and fire taps.
var touch_move := Vector2.ZERO
var touch_jump := false
var touch_fire := false
var touch_punch := false
var touch_kick := false
var touch_dodge := false
## Set by TouchControls and scripted runs: sprint without the key.
var touch_sprint := false
var cooldown_left := 0.0
## Where the camera looks (rad): `yaw` about the vertical (0 is along -Z),
## `pitch` up (positive) or down.
var yaw := 0.0
var pitch := -0.15
## Where the character faces (rad, like `yaw`).
var facing := 0.0
var camera: Camera3D
var character: Character
## What its blows do, and what happens when it takes one (see Fighter).
var fighter: Fighter
## Set by the world, to shove loose pieces aside.
var pieces: Pieces

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn: Transform3D
var _lift := 0.0  # the view and the body lag behind a step up, so they do not jump
var _pivot: Node3D  # turns with `yaw`, at head height
var _arm: Node3D  # tilts with `pitch`
var _shoulder := SHOULDER
var _back := BACK
var _aim_left := 0.0
var _airborne := 0.0  # s since the feet left the ground
var _fell := 0.0  # m/s down, just before landing
var _wish := Vector3.ZERO  # where the stick pushes, in the world
var _opponent: Node3D  # who the strike under way goes for
var _punch_to := 0.0  # where it is thrown (rad, like `facing`)


func _init() -> void:
	collision_layer = Structure.LAYER_PLAYER
	collision_mask = (
		Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS | Structure.LAYER_ACTOR
	)
	floor_snap_length = 0.3
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
	fighter = Fighter.new(self, character)
	character.swung.connect(_on_swung)
	character.struck.connect(func(move: String) -> void: fighter.strike(move, facing))
	_pose_camera()


func _ready() -> void:
	add_to_group("player")
	add_to_group(Fighter.GROUP)
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
		elif event.is_action_pressed("punch"):
			punch()
	elif event.is_action_pressed("fire"):
		fire()
	elif event.is_action_pressed("punch"):
		punch()
	elif event.is_action_pressed("kick"):
		kick()
	elif event.is_action_pressed("dodge"):
		dodge()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Turns the camera: x to the left, y up (rad).
func look(delta_angles: Vector2) -> void:
	yaw = wrapf(yaw + delta_angles.x, -PI, PI)
	pitch = clampf(pitch + delta_angles.y, LOOK_DOWN, LOOK_UP)
	_pose_camera()


## Turns the camera so that the crosshair is on `target`.
func look_at_point(target: Vector3) -> void:
	# The camera is beside the point it turns about, so its line of sight
	# does not go through that point: a few rounds get it onto the target.
	for k in 4:
		var d := target - camera.global_position
		yaw = atan2(-d.x, -d.z)
		pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), LOOK_DOWN, LOOK_UP)
		_pose_camera()


## The first thing under the crosshair, beyond the character (or the end of
## a shot's range).
func aim_point() -> Vector3:
	var along := -camera.global_basis.z
	var eye := camera.global_position
	# From where the line of sight passes the character, not from the camera:
	# what stands between the two is not what is aimed at.
	var from := eye + along * maxf((_pivot.global_position - eye).dot(along), 0.0)
	var to := from + along * Projectile.RANGE
	var mask := (
		Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS | Structure.LAYER_ACTOR
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, mask)
	)
	return to if hit.is_empty() else hit["position"]


## Shoots at what is under the crosshair, if the last shot is far enough
## behind. The character turns to it.
func fire() -> bool:
	if cooldown_left > 0.0 or character.busy() or not fighter.up():
		return false
	cooldown_left = COOLDOWN
	var from := global_position + Vector3.UP * CHEST
	var along := -camera.global_basis.z
	var way := (aim_point() - from).normalized()
	if way.dot(along) < 0.3:
		way = along  # aimed at something beside or behind the chest
	_aim_left = AIM_HOLD
	character.shoot()
	fired.emit(from, way)
	return true


## Throws a punch (see Character.punch), feet on the ground.
func punch() -> bool:
	return fighter.up() and is_on_floor() and character.punch()


## A kick, feet on the ground.
func kick() -> bool:
	return fighter.up() and is_on_floor() and character.kick()


## Ducks, feet on the ground.
func dodge() -> bool:
	return fighter.up() and is_on_floor() and character.dodge()


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if fighter.step(delta):
		# Knocked off its feet: nothing to steer until it is up again.
		touch_fire = false
		touch_punch = false
		touch_kick = false
		touch_dodge = false
		touch_jump = false
		_airborne = 0.0
		character.rotation.y = facing
		_pose_camera(delta)
		return
	var stick := Vector2.ZERO
	var move := Vector2.ZERO
	if input_enabled:
		stick = Input.get_vector("look_right", "look_left", "look_down", "look_up")
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		move = (move + touch_move).limit_length(1.0)
		if touch_fire:
			fire()
		if touch_punch:
			punch()
		if touch_kick:
			kick()
		if touch_dodge:
			dodge()
	touch_fire = false
	touch_punch = false
	touch_kick = false
	touch_dodge = false
	if stick != Vector2.ZERO:
		# Squared response curve gives fine aim near the centre.
		look(stick * stick.length() * stick_sensitivity * delta)

	# Where you push, seen from the camera. How far you push sets the pace.
	var wish := (Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)).limit_length(1.0)
	_wish = wish
	var sprinting := touch_sprint or Input.is_action_pressed("sprint")
	var speed := sprint_speed if input_enabled and sprinting else run_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var busy := character.busy()
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if busy:
		horizontal = Fighter.move_speed(self, character, _opponent, delta)
	else:
		horizontal = horizontal.move_toward(wish * speed, accel * delta)
		if wish.length() > 0.1:
			character.relax()  # walking away from the guard
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var grounded := is_on_floor()
	if grounded:
		if input_enabled and not busy and (Input.is_action_just_pressed("jump") or touch_jump):
			velocity.y = jump_velocity
			character.jump()
	else:
		velocity.y -= _gravity * delta
		_fell = maxf(-velocity.y, 0.0)
	touch_jump = false
	move_and_slide()
	_climb(wish, delta)
	_lift = move_toward(_lift, 0.0, delta * 3.0)
	_shove()
	if global_position.y < KILL_Y:
		global_transform = _spawn
		velocity = Vector3.ZERO
	_animate(wish, delta)
	_pose_camera(delta)


## Turns the character and tells it what its legs are doing.
func _animate(wish: Vector3, delta: float) -> void:
	_aim_left = maxf(_aim_left - delta, 0.0)
	if character.busy():
		if is_instance_valid(_opponent):
			var d := _opponent.global_position - global_position
			_punch_to = atan2(-d.x, -d.z)
		facing = rotate_toward(facing, _punch_to, TURN * delta)
	elif _aim_left > 0.0:
		facing = rotate_toward(facing, yaw, TURN * 3.0 * delta)
	elif wish.length() > 0.1:
		var to := atan2(-wish.x, -wish.z)
		facing = rotate_toward(facing, to, TURN * delta)
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


## A strike starts: it is thrown where the stick pushes (or where the
## character faces), at the other brute if it is there.
func _on_swung(_move: String) -> void:
	_aim_left = 0.0
	_punch_to = atan2(-_wish.x, -_wish.z) if _wish.length() > 0.1 else facing
	var ahead := Basis(Vector3.UP, _punch_to) * Vector3.FORWARD
	_opponent = null
	var nearest := SEEK
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var other := node as Node3D
		var d := other.global_position - global_position
		var off := Vector3(d.x, 0, d.z)
		if other == self or absf(d.y) > 1.0 or off.length() >= nearest:
			continue
		if not (other.get("fighter") as Fighter).up():
			continue
		if off.length() > 0.01 and ahead.angle_to(off) > CONE:
			continue
		nearest = off.length()
		_opponent = other


## Puts the camera behind the shoulder, nearer when something is in
## the way (it goes in at once and eases back out over `delta`).
func _pose_camera(delta := 0.0) -> void:
	_pivot.position.y = HEAD - _lift
	_pivot.rotation.y = yaw
	_arm.rotation.x = pitch
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		var mask := Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
		var head := _pivot.global_position
		var side := _arm.global_basis.x * SIDE
		var up := _arm.global_basis.y
		var back := _arm.global_basis.z
		# To the shoulder first, then back from there.
		var shoulder := SHOULDER
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(head, head + side * (SHOULDER + ROOM), mask)
		)
		if not hit.is_empty():
			shoulder = maxf(head.distance_to(hit["position"]) - ROOM, 0.0)
		var from := head + side * shoulder
		var away := BACK
		var reach := (back * BACK + up * RAISED).normalized()
		var length := Vector2(BACK, RAISED).length()
		hit = space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + reach * (length + ROOM), mask)
		)
		if not hit.is_empty():
			away = maxf(from.distance_to(hit["position"]) - ROOM, 0.0) / length * BACK
		_shoulder = minf(shoulder, move_toward(_shoulder, shoulder, EASE_OUT * delta))
		_back = minf(away, move_toward(_back, away, EASE_OUT * delta))
	camera.position = Vector3(_shoulder * SIDE, RAISED * _back / BACK, _back)
	character.visible = _back > TOO_CLOSE


## Stopped by something low while walking: step up onto it.
func _climb(wish: Vector3, delta: float) -> void:
	if wish.length() < 0.2:
		return
	var rise := Fighter.climb(self, wish.normalized(), maxf(run_speed * delta, 0.15), STEP)
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
