class_name Player
extends CharacterBody3D
## The brute, as you steer it: a third-person controller (mouse + keyboard,
## gamepad, touch). You look around with the camera, which sits behind the
## character's left shoulder; the character goes where you push, relative to
## the camera, and turns to face where it goes. The punch button throws a
## blow, then the next of the combination if it is pressed again, and so
## on. While such a move plays, the body goes where the move steps
## (Character.root_motion).
##
## A blow lands where its fist first touches something on its way, not
## where the move ends: the fist is followed step by step from the
## moment it is thrown (Character.reached). If it touches nothing, the
## blow goes to what the arm behind it runs through, then, when the move
## has it land, to what stands between the body and the fist.
##
## What a blow does to what it lands on is not decided here: the brute says
## where it landed, on what and how hard (`blow`), and that takes it.

## A blow lands at `at`, on the body `on` (an empty RID: on nothing; `at`
## is then where the fist ended). It was thrown along `way`, `power` hard
## (2 a blow, 3 a heavy one).
signal blow(at: Vector3, way: Vector3, power: int, on: RID)

const FOV := 70.0
## Something up to this high (m) is stepped onto instead of stopping you,
## with a stride of up to STRIDE (m).
const STEP := 0.6
const STRIDE := 0.35
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
## The brute is this wide where it stands (m, the radius of its capsule).
const RADIUS := 0.35
## No part of it goes farther ahead of where it stands than this in a move
## (m; the most is its left hand in the leap, 0.8 m; with room to
## spare).
const LUNGE := 1.1
## A fist is a ball this wide round the knuckles (m, its radius).
const FIST := 0.1
## What stands between the body and a fist that touched nothing on its way
## is looked for this wide (m, a radius): the arm and the shoulder.
const ARM := 0.2
## What comes down on the brute pushes it out from under at this speed
## (m/s): it does not hold up what falls on it.
const GIVE_WAY := 3.0

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
var _pushed := Vector3.ZERO  # the way something that came down on it pushes it, this step
var _pushed_by := 0.0  # how heavy that is (kg): the heaviest has its way
var _lift := 0.0  # the view and the body lag behind a step up, so they do not jump
var _pivot: Node3D  # turns with `yaw`, at head height
var _arm: Node3D  # tilts with `pitch`
var _shoulder := SHOULDER
var _back := BACK
var _airborne := 0.0  # s since the feet left the ground
var _fell := 0.0  # m/s down, just before landing
var _wish := Vector3.ZERO  # where the stick pushes, in the world
var _punch_to := 0.0  # where the strike under way is thrown (rad, like `facing`)
var _fist_was := Vector3.INF  # where its fist or foot was a step ago (not thrown yet: INF)
var _ball := SphereShape3D.new()
var _sight := PhysicsRayQueryParameters3D.new()  # what the camera stays in front of
var _set_down := 0  # steps left during which it touches nothing, having been set down


func _init() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.STRUCTURE | Layers.RUBBLE
	floor_snap_length = 0.3
	# A block that goes off under its feet does not take it along.
	platform_floor_layers = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
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
	character.posed.connect(_on_posed)
	character.reached.connect(_on_reached)
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
	elif event.is_action_pressed("punch"):
		punch()
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


## Something has come down on the brute, `weight` kg of it, its middle at
## `from`: the brute is pushed out from under it, away from that middle
## (under a plate that sags, that is towards where it is still high). If
## several things do, the heaviest has its way.
func give_way(from: Vector3, weight: float) -> void:
	if weight <= _pushed_by:
		return
	var out := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if out.length() < 0.05:
		out = Basis(Vector3.UP, facing) * Vector3.BACK
	_pushed = out.normalized()
	_pushed_by = weight


## Throws a blow, or asks for the next of the combination (see
## Character.punch). Returns false if it cannot: only feet on the ground.
func punch() -> bool:
	return is_on_floor() and character.punch()


## Sets the brute down at `at`, wherever it was: a scripted run does, the
## bench put back does. It touches nothing for the two steps this takes:
## a body moved from one step to the next is taken to have gone there in
## that step, and throws what lay against it (a block of 55 kg left at
## 270 m/s).
func set_down(at: Vector3) -> void:
	collision_layer = 0
	collision_mask = 0
	_set_down = 2
	global_position = at
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _set_down > 0:
		_set_down -= 1
		if _set_down > 0:
			return
		collision_layer = Layers.PLAYER
		collision_mask = Layers.WORLD | Layers.STRUCTURE | Layers.RUBBLE
	var stick := Input.get_vector("look_right", "look_left", "look_down", "look_up")
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move = (move + touch_move).limit_length(1.0)
	if touch_punch:
		punch()
	touch_punch = false
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
	var pushed := _pushed
	_pushed = Vector3.ZERO
	_pushed_by = 0.0
	if pushed != Vector3.ZERO:
		# Under something that comes down, it goes where that sends it.
		horizontal = pushed * GIVE_WAY
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
	_climb(horizontal.limit_length(1.0) if busy or pushed != Vector3.ZERO else wish, delta)
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
	_fist_was = Vector3.INF


## The pose of a step of a strike is set. The moves lunge well ahead of
## where the brute stands (its left hand 0.8 m, its head 0.5 m in the
## leap): it is held back from what stands, so that only the limb that
## strikes goes into it.
func _on_posed() -> void:
	var ahead := Basis(Vector3.UP, facing) * Vector3.FORWARD
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _ball
	query.collision_mask = Layers.STRUCTURE
	# (Nothing stands within a lunge of it: nothing to look for.)
	_ball.radius = LUNGE
	query.transform = Transform3D(Basis(), global_position + ahead * LUNGE * 0.5 + Vector3.UP)
	if space.intersect_shape(query, 1).is_empty():
		return
	var deep := 0.0
	for part in character.bulk():
		var at := Vector3(part.x, part.y, part.z)
		var out := (at - global_position).dot(ahead)
		if out + part.w <= RADIUS:
			continue  # the body, where it stands, keeps that out already
		# As wide as it is, from beside the brute where it stands, straight
		# ahead, to where it is drawn: how far before it meets something.
		_ball.radius = part.w
		query.transform = Transform3D(Basis(), at - ahead * out)
		query.motion = ahead * out
		var free := space.cast_motion(query)
		# (Nothing in the way, or in something from the start: beside a
		# column, say. Neither is the lunge going into what is ahead.)
		if free[1] < 1.0 and free[1] > 0.0:
			deep = maxf(deep, out * (1.0 - free[0]))
	if deep > 0.0:
		move_and_collide(-ahead * deep)


## The fist of the strike under way is at the end of `limb` (see
## Character.limb). What it touches on its way there takes the blow, there
## and then; `there`: the move has it land now, on something or not.
func _on_reached(limb: PackedVector3Array, there: bool) -> void:
	var fist := limb[2]
	var was := _fist_was if _fist_was.is_finite() else fist
	_fist_was = fist
	var ahead := Basis(Vector3.UP, facing) * Vector3.FORWARD
	# It counts once it is in front of the body: not drawn back behind it.
	var out := (fist - global_position).dot(ahead)
	var out_was := (was - global_position).dot(ahead)
	var met := {}
	if out > 0.0:
		if out_was < 0.0:
			was = was.lerp(fist, out_was / (out_was - out))
		met = _touched(was, fist, limb)
	if met.is_empty() and there:
		met = _between(limb)
	if met.is_empty() and not there:
		return
	character.landed()
	blow.emit(met.get("at", fist), ahead, character.power(), met.get("on", RID()))


## What the fist touches as it goes from `from` to `to`, or else what the
## arm behind it runs through as it is now (`limb`): where ("at") and what
## ("on"). Empty: nothing.
func _touched(from: Vector3, to: Vector3, limb: PackedVector3Array) -> Dictionary:
	var met := _swept(from, to, FIST)
	if not met.is_empty():
		return met
	var space := get_world_3d().direct_space_state
	for k: int in [1, 0]:
		var run := PhysicsRayQueryParameters3D.create(limb[k], limb[k + 1], Layers.STRUCTURE | Layers.RUBBLE)
		var through := space.intersect_ray(run)
		if not through.is_empty():
			return {"at": through["position"], "on": through["rid"]}
	return {}


## What stands between the body and the end of `limb`, at the height the
## limb leaves the body at: where ("at") and what ("on"). Empty: nothing.
func _between(limb: PackedVector3Array) -> Dictionary:
	return _swept(Vector3(global_position.x, limb[0].y, global_position.z), limb[2], ARM)


## The first thing a ball `wide` in radius touches as it goes from `from`
## to `to`: where ("at") and what ("on"). Empty: nothing.
func _swept(from: Vector3, to: Vector3, wide: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	_ball.radius = wide
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _ball
	query.collision_mask = Layers.STRUCTURE | Layers.RUBBLE
	query.transform = Transform3D(Basis(), from)
	query.motion = to - from
	var free := space.cast_motion(query)
	if free[1] >= 1.0:
		return {}
	query.transform.origin = from + (to - from) * free[1]
	query.motion = Vector3.ZERO
	var rest := space.get_rest_info(query)
	if not rest.is_empty():
		return {"at": rest["point"], "on": rest["rid"]}
	var touching := space.intersect_shape(query, 1)
	if touching.is_empty():
		return {}
	return {"at": query.transform.origin, "on": touching[0]["rid"]}


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
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP):
		return  # no headroom
	xf.origin.y += STEP
	# A short stride onto it; if all that is under the foot there is an
	# edge (the uneven foot of a wall that was knocked open), a longer one.
	var landing := KinematicCollision3D.new()
	var to := Vector3.INF
	for stride: float in [maxf(run_speed * delta, 0.15), STRIDE]:
		if test_move(xf, way * stride):
			break  # too high to step onto
		var over := xf.translated(way * stride)
		if test_move(over, Vector3.DOWN * STEP, landing) and landing.get_normal().y >= 0.6:
			to = over.origin + landing.get_travel()
			break
	if not to.is_finite():
		return  # nothing flat enough up there
	var rise := to.y - global_position.y
	if rise < 0.03:
		return
	global_position = to
	_lift = minf(_lift + rise, STEP)
