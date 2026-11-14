class_name Dummy
extends CharacterBody3D
## Someone to hit: a mannequin that stands there and turns to whoever is
## near. A punch or a shot makes it flinch and pushes it back; after a few
## it falls on its back, lies there a moment and gets up again.

const GROUP := "opponent"
const BODY := Color(0.8, 0.36, 0.26)
const JOINTS := Color(0.22, 0.2, 0.2)
## What it takes before it goes down: a jab counts for 1, a harder punch or
## a shot for 2, a kick for 3. The four punches of the combination make 7.
const BLOWS := 7
## A blow pushes it back this fast (m/s) for each point it counts for, and
## it slows down at SLOWS m/s2: a few centimetres for a jab, half a metre
## for a kick.
const PUSHED := 1.0
const SLOWS := 8.0
## It turns at TURN rad/s to whoever is nearer than NOTICE m.
const TURN := 5.0
const NOTICE := 8.0
## Knocked down, it turns its back to where the blow goes while it still
## staggers (FALL_TURNS s, at FALL_TURN rad/s), is flat on the ground after
## FALLS s and stays there LIES s (and half a second more: the start of
## getting up, which is the end of the fall, is still).
const FALL_TURN := 12.0
const FALL_TURNS := 0.4
const FALLS := 1.5
const LIES := 1.5

var character: Character
## Who it turns to (set by the world).
var watches: Node3D
var blows_left := BLOWS
## Where it faces (rad about the vertical; 0 is along -Z).
var facing := 0.0
## "up", "down" (falling, then lying) or "rising".
var state := "up"

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _for := 0.0  # s in the current state
var _rises := 0.0  # s it takes to get up
var _fall_to := 0.0  # where it faces to fall along the blow


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


func _ready() -> void:
	add_to_group(GROUP)
	character.paint(BODY, JOINTS)
	if watches != null:
		facing = _towards(watches.global_position)
	character.rotation.y = facing


## A blow going along `way`, that counts for `power` (see BLOWS). Returns
## false if it is not standing to take it.
func take_hit(way: Vector3, power: int) -> bool:
	if state != "up":
		return false
	blows_left -= power
	var flat := Vector3(way.x, 0, way.z).normalized()
	if blows_left > 0:
		character.hit(power > 1)
		velocity += flat * PUSHED * power
		return true
	state = "down"
	_for = 0.0
	# It falls on its back: its back goes where the blow goes.
	_fall_to = atan2(flat.x, flat.z) if flat != Vector3.ZERO else facing
	velocity = flat * PUSHED
	collision_layer = 0  # nothing to walk into or to hit while it is down
	character.down()
	return true


func _physics_process(delta: float) -> void:
	_for += delta
	if state == "up":
		if watches != null and watches.global_position.distance_to(global_position) < NOTICE:
			facing = rotate_toward(facing, _towards(watches.global_position), TURN * delta)
	elif state == "down":
		if _for < FALL_TURNS:
			facing = rotate_toward(facing, _fall_to, FALL_TURN * delta)
		if _for > FALLS + LIES:
			state = "rising"
			_for = 0.0
			_rises = character.up()
	elif _for > _rises:
		state = "up"
		blows_left = BLOWS
		collision_layer = Structure.LAYER_ACTOR
	character.rotation.y = facing
	var flat := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, SLOWS * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


## The facing that looks at `point`.
func _towards(point: Vector3) -> float:
	var to := point - global_position
	return facing if Vector2(to.x, to.z).length() < 0.01 else atan2(-to.x, -to.z)
