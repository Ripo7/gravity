class_name Brute
extends CharacterBody3D
## The other brute: a mannequin in red that walks up to whoever it watches
## and throws the same moves, and takes them too (see Fighter).

const BODY := Color(0.8, 0.36, 0.26)
const JOINTS := Color(0.22, 0.2, 0.2)
## It walks up at PACE m/s until it is RANGE m away, then strikes: a kick
## (KICKS of the time) or one to three blows of the combination, with a
## wait between two attacks (WAITS: from, to, in s).
const PACE := 3.2
const RANGE := 1.15
const KICKS := 0.3
const WAITS := Vector2(0.5, 1.3)
## It turns at TURN rad/s to whoever is nearer than NOTICE m.
const TURN := 6.0
const NOTICE := 60.0
const QUICKENS := 20.0  ## m/s2
## Rubble up to STEP m high is stepped onto. Stopped by something on its
## way, it goes through (Fighter.breach), with a kick for show.
const STEP := 0.6

var character: Character
var fighter: Fighter
## Who it turns to and fights (set by the world).
var watches: Node3D
## It attacks. Off, it only stands there and takes blows.
var ai := true
## Where it faces (rad about the vertical; 0 is along -Z).
var facing := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _wait := 1.0  # s before its next attack
var _more := 0  # punches still to chain
var _last := ""  # the move it was in at the last step
var _stuck := 0.0  # s it has been stopped on its way


func _init() -> void:
	collision_layer = Structure.LAYER_ACTOR
	collision_mask = (
		Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS | Structure.LAYER_PLAYER
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
	fighter = Fighter.new(self, character)
	character.struck.connect(func(move: String) -> void: fighter.strike(move, facing))


func _ready() -> void:
	add_to_group(Fighter.GROUP)
	character.paint(BODY, JOINTS)
	if watches != null:
		facing = _towards(watches.global_position)
	character.rotation.y = facing


func _physics_process(delta: float) -> void:
	if fighter.held():
		return
	if fighter.step(delta):
		character.rotation.y = facing
		return
	var seen := watches != null and watches.global_position.distance_to(global_position) < NOTICE
	var busy := character.busy()
	var to := Vector3.ZERO
	if seen and (not busy or character.lands_in() > 0.0):
		facing = rotate_toward(facing, _towards(watches.global_position), TURN * delta)
	if busy:
		to = Fighter.move_speed(self, character, watches if seen else null, delta)
		if character.state != _last and _more > 0 and character.state in Character.COMBO:
			character.punch()  # the next one of the combination is asked for
			_more -= 1
		_last = character.state
	elif ai and seen:
		to = _fight(delta)
	var flat := Vector3(velocity.x, 0, velocity.z)
	flat = to if busy else flat.move_toward(to, QUICKENS * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	character.rotation.y = facing
	if busy:
		if to.length() > 1.0:
			Fighter.climb(self, to.normalized(), 0.15, STEP)  # a blow steps onto rubble too
		return
	var pace := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	character.move(pace)
	if to.length() < 1.0:
		_stuck = 0.0
		return
	# Rubble in the way: it steps onto it. A wall: it goes through.
	var ahead := to.normalized()
	Fighter.climb(self, ahead, 0.15, STEP)
	_stuck = _stuck + delta if pace < 0.6 else 0.0
	if _stuck > Fighter.STUCK:
		_stuck = 0.0
		_more = 0
		character.kick()
		fighter.breach(ahead)


## Up to who it fights, then an attack now and then. Returns the speed
## over the ground it wants.
func _fight(delta: float) -> Vector3:
	var d := watches.global_position - global_position
	d.y = 0.0
	_wait -= delta
	if d.length() > RANGE:
		character.relax()
		return d.normalized() * PACE
	if _wait <= 0.0 and is_on_floor() and (watches.get("fighter") as Fighter).up():
		_wait = randf_range(WAITS.x, WAITS.y)
		_last = ""
		if randf() < KICKS:
			_more = 0
			character.kick()
		else:
			_more = randi_range(0, Character.COMBO.size() - 1)
			character.punch()
	return Vector3.ZERO


## The facing that looks at `point`.
func _towards(point: Vector3) -> float:
	var to := point - global_position
	return facing if Vector2(to.x, to.z).length() < 0.01 else atan2(-to.x, -to.z)
