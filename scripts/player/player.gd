class_name Player
extends CharacterBody3D
## Third-person controller (mouse + keyboard, gamepad, touch). You look
## around with the camera, which sits behind the character's left shoulder;
## the character goes where you push, relative to the camera, and turns to
## face where it goes. The punch button throws a blow, then the next of the
## combination if it is pressed again, and so on; there is a kick too, and
## a guard for as long as its button is held. A strike goes for the
## opponent in front, stepping in if it is a little too far. While such a
## move plays, the body goes where the move steps (Character.root_motion).
##
## Locked on the other brute (see lock), the camera stays on it and a
## strike asked for from too far runs at it first, so that it lands.

const FOV := 70.0
const KILL_Y := -25.0
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
## The character turns to where it goes at this rate (rad/s).
const TURN := 12.0
## In the air this long (s) without having jumped: it is a fall.
const FALL_AFTER := 0.12
## A strike goes for the nearest other brute within SEEK m, if it is less
## than CONE rad off where it is thrown (see Fighter for what it does).
const SEEK := 2.4
const CONE := 1.2
## Locked on (see `lock`), the camera closes LOCK_TURN of its angle to the
## other brute every second and looks LOCK_TILT rad below the line to it
## and LOCK_SIDE rad to the right of it, so that the two are seen side by
## side and not one behind the other; a strike always goes to it. Asked for from farther than it reaches, the
## character runs at the other first and strikes once the blow would land
## with a step of STEP_IN m at most and nothing stands between them (looked
## for CHEST m up); it gives up after CHARGE_MOST s. Held up HELD_UP s by
## what stands on its way there, it goes through (Fighter.breach).
const LOCK_RANGE := 60.0
const LOCK_TURN := 7.0
const LOCK_TILT := -0.2
const LOCK_SIDE := 0.6
const STEP_IN := 0.5
const CHEST := 1.1
const CHARGE_MOST := 4.0
const HELD_UP := 0.15
## A jolt (Fighter.jolted, 0 to 1) shakes the camera: SHAKE rad for the
## hardest, less by the square, dying out in SHAKE_FOR s.
const SHAKE := 0.05
const SHAKE_FOR := 0.35

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
## Set by TouchControls: stick vector (x right, y back), and taps.
var touch_move := Vector2.ZERO
var touch_jump := false
var touch_punch := false
var touch_kick := false
## Set by TouchControls and scripted runs: the guard is held.
var touch_guard := false
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
## What its blows do, and what happens when it takes one (see Fighter).
var fighter: Fighter
## The other brute it is locked on, if any (see `lock`).
var locked: Node3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn: Transform3D
var _lift := 0.0  # the view and the body lag behind a step up, so they do not jump
var _pivot: Node3D  # turns with `yaw`, at head height
var _arm: Node3D  # tilts with `pitch`
var _shoulder := SHOULDER
var _back := BACK
var _airborne := 0.0  # s since the feet left the ground
var _fell := 0.0  # m/s down, just before landing
var _wish := Vector3.ZERO  # where the stick pushes, in the world
var _opponent: Node3D  # who the strike under way goes for
var _punch_to := 0.0  # where it is thrown (rad, like `facing`)
var _charge := ""  # the strike to throw on reaching who it is locked on
var _charge_for := 0.0  # s it has been running at it
var _stopped := 0.0  # s it has been stopped by something on the way there
var _mark: MeshInstance3D  # the ring at the feet of who it is locked on
var _guarded := false  # the guard was asked for at the last step
var _shake := 0.0  # how much the camera shakes (1 to 0)
var _shaken := 0.0  # s it has shaken in all: where its tremor is


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
	# The ring at the feet of who it is locked on.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.58
	ring.rings = 32
	ring.ring_segments = 6
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_color = Color(1.0, 0.7, 0.15)
	ring.material = lit
	_mark = MeshInstance3D.new()
	_mark.mesh = ring
	_mark.top_level = true
	_mark.visible = false
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mark)
	fighter = Fighter.new(self, character)
	fighter.jolted.connect(shake)
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
		elif event.is_action_pressed("lock"):
			lock()
	elif event.is_action_pressed("punch"):
		punch()
	elif event.is_action_pressed("kick"):
		kick()
	elif event.is_action_pressed("lock"):
		lock()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Turns the camera: x to the left, y up (rad).
func look(delta_angles: Vector2) -> void:
	if locked != null:
		return  # the camera is on the other brute
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


## A blow has landed, been taken or broken a wall: the camera shakes,
## `amount` (0 to 1) of the most it can.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Locks on the nearest other brute, or lets go of the one it is locked
## on. Locked, the camera stays on it and strikes go to it.
func lock() -> void:
	_charge = ""
	if locked != null:
		locked = null
		return
	var nearest := LOCK_RANGE
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var other := node as Node3D
		var far := other.global_position.distance_to(global_position)
		if other != self and far < nearest:
			nearest = far
			locked = other


## Throws a punch (see Character.punch), feet on the ground.
func punch() -> bool:
	return _strike("punch")


## A kick, feet on the ground.
func kick() -> bool:
	return _strike("kick")


## The guard, for as long as `on`: fists up in front of the face, feet
## still, turned to who it is locked on. A blow from the front is blocked
## (Fighter.take_hit). Taking it up calls a run off; a strike asked for
## from it lets it go for as long as the strike takes.
func guard(on: bool) -> void:
	if on and not _guarded:
		_charge = ""
	_guarded = on
	character.guard(on and _charge == "" and fighter.up() and is_on_floor())


func _physics_process(delta: float) -> void:
	if fighter.held():
		# The instant a blow lands: nothing moves, what is pressed waits.
		_track(delta)
		_pose_camera(delta)
		return
	if fighter.step(delta):
		# Knocked off its feet: nothing to steer until it is up again.
		touch_punch = false
		touch_kick = false
		touch_jump = false
		_airborne = 0.0
		character.rotation.y = facing
		_track(delta)
		_pose_camera(delta)
		return
	var stick := Vector2.ZERO
	var move := Vector2.ZERO
	if input_enabled:
		stick = Input.get_vector("look_right", "look_left", "look_down", "look_up")
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		move = (move + touch_move).limit_length(1.0)
		if touch_punch:
			punch()
		if touch_kick:
			kick()
	guard(input_enabled and (touch_guard or Input.is_action_pressed("guard")))
	touch_punch = false
	touch_kick = false
	if stick != Vector2.ZERO:
		# Squared response curve gives fine aim near the centre.
		look(stick * stick.length() * stick_sensitivity * delta)

	# Where you push, seen from the camera. How far you push sets the pace.
	var wish := (Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)).limit_length(1.0)
	_wish = wish
	var charging := _charging(delta)
	if charging != Vector3.ZERO:
		wish = charging  # running at who it is locked on: the stick waits
	elif character.guarding():
		wish = Vector3.ZERO  # the guard is held standing
	var sprinting := touch_sprint or Input.is_action_pressed("sprint")
	var speed := sprint_speed if charging != Vector3.ZERO or (input_enabled and sprinting) else run_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var busy := character.striking()
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if busy:
		horizontal = Fighter.move_speed(self, character, _opponent, delta)
	else:
		horizontal = horizontal.move_toward(wish * speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var grounded := is_on_floor()
	if grounded:
		var free := not busy and not character.guarding()
		if input_enabled and free and (Input.is_action_just_pressed("jump") or touch_jump):
			_charge = ""
			velocity.y = jump_velocity
			character.jump()
	else:
		velocity.y -= _gravity * delta
		_fell = maxf(-velocity.y, 0.0)
	touch_jump = false
	move_and_slide()
	# Where it means to go, and how fast (held up, it has no speed of its own).
	var going := horizontal if busy or wish == Vector3.ZERO else wish * speed
	var waded := fighter.wade(going, horizontal)
	var pushing := charging
	if busy and horizontal.length() > 1.0 and _target() != null:
		pushing = horizontal.normalized()  # the step of a blow that goes to it
	_go_through(pushing, delta)
	# A blow that steps in steps onto rubble like any other step. (Not onto
	# what it has just walked through.)
	if not waded:
		_climb(horizontal.limit_length(1.0) if busy else wish, delta)
	_lift = move_toward(_lift, 0.0, delta * 3.0)
	if global_position.y < KILL_Y:
		global_transform = _spawn
		velocity = Vector3.ZERO
	_animate(wish, delta)
	_track(delta)
	_pose_camera(delta)


## Turns the character and tells it what its legs are doing.
func _animate(wish: Vector3, delta: float) -> void:
	if character.striking():
		if is_instance_valid(_opponent):
			var d := _opponent.global_position - global_position
			_punch_to = atan2(-d.x, -d.z)
		facing = rotate_toward(facing, _punch_to, TURN * delta)
	elif character.guarding():
		var against := _target()
		if against != null:
			var d := against.global_position - global_position
			facing = rotate_toward(facing, atan2(-d.x, -d.z), TURN * delta)
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
	_opponent = _target()
	if _opponent != null:
		return  # locked on: it goes to it, wherever the stick pushes
	_punch_to = atan2(-_wish.x, -_wish.z) if _wish.length() > 0.1 else facing
	var ahead := Basis(Vector3.UP, _punch_to) * Vector3.FORWARD
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


## The brute it is locked on, if it is on its feet.
func _target() -> Node3D:
	if not is_instance_valid(locked):
		locked = null
		return null
	return locked if (locked.get("fighter") as Fighter).up() else null


## A punch or a kick is asked for. Locked on a brute too far for it, the
## character runs at it first (see `_charging`).
func _strike(kind: String) -> bool:
	if not fighter.up() or not is_on_floor():
		return false
	if _target() != null and not character.striking() and not _within(kind):
		_charge = kind
		_charge_for = 0.0
		return true
	_charge = ""
	return character.punch() if kind == "punch" else character.kick()


## Would the strike `kind`, thrown from here, land on who it is locked on?
## It is near enough, and nothing stands between them.
func _within(kind: String) -> bool:
	if _short_by(kind) > 0.0:
		return false
	var up := Vector3.UP * CHEST
	var ray := PhysicsRayQueryParameters3D.create(
		global_position + up, locked.global_position + up, Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
	)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## How far short (m) of who it is locked on the strike `kind` would stop,
## thrown from here: beyond its reach and the short step that goes with it.
func _short_by(kind: String) -> float:
	var first := Character.COMBO[0] if kind == "punch" else "kick"
	var d := locked.global_position - global_position
	d.y = 0.0
	var closes := minf(Fighter.LUNGE * character.lands_after(first), STEP_IN)
	return d.length() - character.about(first, "reach") - Fighter.CONTACT - closes


## Running at who it is locked on, to throw the strike that was asked for:
## returns where to (a unit vector), or nothing once it is thrown or given
## up.
func _charging(delta: float) -> Vector3:
	if _charge == "":
		return Vector3.ZERO
	_charge_for += delta
	if _target() == null or _charge_for > CHARGE_MOST or character.striking():
		_charge = ""
		return Vector3.ZERO
	if _within(_charge):
		# (Not while it is in the air off a heap of rubble: on landing.)
		if character.punch() if _charge == "punch" else character.kick():
			_charge = ""
			return Vector3.ZERO
	var d := locked.global_position - global_position
	d.y = 0.0
	return d.normalized()


## Going at who it is locked on (`way`, nothing otherwise) and held up by
## what stands: it goes through. (Up against the other brute itself, it
## has arrived.)
func _go_through(way: Vector3, delta: float) -> void:
	var pace := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	var held := way != Vector3.ZERO and pace < 1.0
	for k in get_slide_collision_count():
		if get_slide_collision(k).get_collider() == locked:
			held = false
	_stopped = _stopped + delta if held else 0.0
	if _stopped > HELD_UP:
		_stopped = 0.0
		fighter.breach(way)


## Locked on, the camera turns to the other brute, and a ring marks it.
func _track(delta: float) -> void:
	if not is_instance_valid(locked):
		locked = null
	_mark.visible = locked != null
	if locked == null:
		return
	_mark.global_position = locked.global_position + Vector3.UP * 0.06
	var d := locked.global_position - global_position
	var flat := Vector2(d.x, d.z).length()
	var closes := 1.0 - exp(-LOCK_TURN * delta)
	if flat > 0.5:
		yaw = lerp_angle(yaw, atan2(-d.x, -d.z) - LOCK_SIDE, closes)
	pitch = lerpf(pitch, clampf(atan2(d.y, maxf(flat, 0.5)) + LOCK_TILT, LOOK_DOWN, LOOK_UP), closes)


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
	_shake = maxf(_shake - delta / SHAKE_FOR, 0.0)
	_shaken += delta
	var tremor := Vector3(sin(_shaken * 110.0), sin(_shaken * 90.0 + 1.0), sin(_shaken * 130.0 + 2.0) * 0.5)
	camera.rotation = tremor * (SHAKE * _shake * _shake)
	character.visible = _back > TOO_CLOSE


## Stopped by something low while walking: step up onto it.
func _climb(wish: Vector3, delta: float) -> void:
	if wish.length() < 0.2:
		return
	var rise := Fighter.climb(self, wish.normalized(), maxf(run_speed * delta, 0.15), STEP)
	_lift = minf(_lift + rise, STEP)
