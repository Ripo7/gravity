class_name Fighter
extends RefCounted
## What the two brutes have in common: what their blows do, to each other
## and to what stands, and what happens to one that is knocked off its
## feet. It flies, goes through whatever is in its way, lands, lies there
## a moment and gets up.
##
## Each brute (the Player, the Brute) is a body with a Character, a
## `facing` and one of these, called `fighter`, and is in GROUP.

const GROUP := "fighter"
## A fist is on the other when it is CONTACT m from its axis; a strike
## that would stop short carries its owner there, at LUNGE m/s at most. It
## counts if the fist is no more than SLACK m short and the other no more
## than WIDE m to either side.
const CONTACT := 0.22
const SLACK := 0.25
const WIDE := 0.5
const LUNGE := 5.0
## The moves that send who takes them flying (the last punch of the
## combination, the kick), at THROW m/s along the ground and LIFT up. The
## others push it back SHOVE m/s for each point of power.
const LAUNCHERS: Array[String] = ["hook_r", "kick"]
const THROW := 12.0
const LIFT := 4.0
const SHOVE := 1.5
## Ducking, a blow higher than this (m) goes over.
const DUCKS_UNDER := 1.2
## What a fist or a foot knocks out of what stands: within this radius
## (m), by power (1 a jab, 2 a punch, 3 a kick).
const HOLE: Array[float] = [0.0, 0.45, 0.7, 1.0]
## Loose pieces within that radius are sent off: RUBBLE kg.m/s for each
## point of power, RUBBLE_MOST m/s at most.
const RUBBLE := 2500.0
const RUBBLE_MOST := 12.0
## In flight, faster than PLOW_FROM m/s, a body knocks out what stands
## within PLOW m of its middle, and each shard takes SLOWED of its speed.
const PLOW := 0.95
const PLOW_FROM := 3.0
const SLOWED := 0.012
## On the ground it slides to a stop (m/s2), lies LIES s, then gets up.
const SLIDES := 14.0
const LIES := 0.7

var body: CharacterBody3D
var character: Character
## What can be broken (set by the world).
var structure: Structure
## "up", or off its feet: "flying", "lying", "rising".
var state := "up"

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _layer := 0
var _mask := 0
var _for := 0.0  # s in the current state
var _rises := 0.0  # s it takes to get up


func _init(of: CharacterBody3D, with: Character) -> void:
	body = of
	character = with
	_layer = of.collision_layer
	_mask = of.collision_mask


func up() -> bool:
	return state == "up"


## The fist or foot of the strike under way is there, the body facing
## `facing`: the brutes and the walls in its way take it.
func strike(move: String, facing: float) -> void:
	var ahead := Basis(Vector3.UP, facing) * Vector3.FORWARD
	var reach := character.reach()
	var power := character.power()
	var height := character.height()
	for node in body.get_tree().get_nodes_in_group(GROUP):
		if node == body:
			continue
		var d: Vector3 = node.global_position - body.global_position
		var along := d.dot(ahead)
		if absf(d.y) < 1.0 and along > 0.0 and along < reach + CONTACT + SLACK:
			if absf(d.cross(ahead).y) < WIDE:
				(node.get("fighter") as Fighter).take_hit(ahead, power, move in LAUNCHERS, height)
	if structure != null:
		var at := body.global_position + ahead * (reach + 0.1) + Vector3.UP * height
		_scatter(at, HOLE[power], ahead, RUBBLE * power)
		clear(ahead, RUBBLE * power)
		smash(structure, at, HOLE[power], ahead * 6.0)


## A blow going along `way`, of `power`, at `height` m. `thrown`: it sends
## the body flying. Returns false if it does not take it (off its feet
## already, or ducking under it).
func take_hit(way: Vector3, power: int, thrown: bool, height := 1.3) -> bool:
	if state != "up" or (character.state == "duck" and height > DUCKS_UNDER):
		return false
	var flat := Vector3(way.x, 0, way.z).normalized()
	if thrown:
		launch(flat * THROW + Vector3.UP * LIFT)
	else:
		character.hit(power > 1)
		body.velocity += flat * SHOVE * power
	return true


## Off its feet, at `velocity`: back first, through what stands.
func launch(velocity: Vector3) -> void:
	state = "flying"
	_for = 0.0
	body.velocity = velocity
	# Only the ground stops it: what stands is broken, the rest is passed.
	body.collision_layer = 0
	body.collision_mask = Structure.LAYER_WORLD
	if Vector2(velocity.x, velocity.z).length() > 0.1:
		body.set("facing", atan2(velocity.x, velocity.z))
	character.blown()


## One physics step of a body that is off its feet. Returns false if it
## is up: its owner moves it.
func step(delta: float) -> bool:
	if state == "up":
		return false
	_for += delta
	var v := body.velocity
	v.y -= _gravity * delta
	var flat := Vector3(v.x, 0, v.z)
	if body.is_on_floor():
		flat = flat.move_toward(Vector3.ZERO, SLIDES * delta)
	if state == "flying":
		if structure != null and flat.length() > PLOW_FROM:
			var middle := body.global_position + Vector3.UP * 0.9
			var broken := smash(structure, middle, PLOW, flat.limit_length(8.0))
			flat *= maxf(1.0 - SLOWED * broken, 0.3)
		if body.is_on_floor() and flat.length() < 0.5 and _for > 0.3:
			state = "lying"
			_for = 0.0
	elif state == "lying":
		if _for > LIES:
			state = "rising"
			_for = 0.0
			_rises = character.up()
	elif _for > _rises:
		state = "up"
		body.collision_layer = _layer
		body.collision_mask = _mask
	body.velocity = Vector3(flat.x, v.y, flat.z)
	body.move_and_slide()
	return true


## Sends off the rubble that lies at its feet, on the side of `ahead`.
func clear(ahead: Vector3, impulse: float) -> void:
	_scatter(body.global_position + ahead * 0.6 + Vector3.UP * 0.4, 0.7, ahead, impulse)


## Sends the loose pieces within `radius` m of `at` off along `way`.
func _scatter(at: Vector3, radius: float, way: Vector3, impulse: float) -> void:
	var ball := SphereShape3D.new()
	ball.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.transform = Transform3D(Basis(), at)
	query.collision_mask = Structure.LAYER_DEBRIS
	var pieces := structure.pieces
	for found in body.get_world_3d().direct_space_state.intersect_shape(query, 12):
		var i := pieces.index_of(found["rid"])
		if i >= 0:
			var speed := minf(impulse / pieces.mass[i], RUBBLE_MOST)
			var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * speed
			pieces.push(i, (way + Vector3.UP * 0.25) * speed, spin)


## The speed over the ground (m/s) of `of` during a boxing move: where the
## move itself steps and, for a strike that would stop short of `opponent`,
## what brings its fist or foot onto it by the time it gets there.
static func move_speed(of: Node3D, with: Character, opponent: Node3D, delta: float) -> Vector3:
	var steps := with.root_motion() / delta
	steps.y = 0.0
	var lands_in := with.lands_in()
	if not is_instance_valid(opponent) or lands_in <= 0.0:
		return steps
	var d := opponent.global_position - of.global_position
	d.y = 0.0
	var gap := d.length() - with.reach() - CONTACT
	if gap <= 0.0:
		return steps
	var towards := d.normalized()
	var needed := minf(gap / maxf(lands_in, delta), LUNGE)
	return steps + towards * maxf(needed - steps.dot(towards), 0.0)


## Stopped by something low while going along `wish` (a unit vector, on
## the ground): `of` steps up onto it, if it is no higher than `height` m and
## there is room. Returns how much it rose (m).
static func climb(of: CharacterBody3D, wish: Vector3, stride: float, height: float) -> float:
	if not of.is_on_floor():
		return 0.0
	var blocked := false
	for k in of.get_slide_collision_count():
		var n := of.get_slide_collision(k).get_normal()
		if absf(n.y) < 0.5 and n.dot(wish) < -0.3:
			blocked = true
	if not blocked:
		return 0.0
	var xf := of.global_transform
	if of.test_move(xf, Vector3.UP * height):
		return 0.0  # no headroom
	xf.origin.y += height
	if of.test_move(xf, wish * stride):
		return 0.0  # too high to height onto
	xf.origin += wish * stride
	var landing := KinematicCollision3D.new()
	if not of.test_move(xf, Vector3.DOWN * height, landing) or landing.get_normal().y < 0.6:
		return 0.0  # nothing flat enough up there
	var to := xf.origin + landing.get_travel()
	var rise := to.y - of.global_position.y
	if rise < 0.03:
		return 0.0
	of.global_position = to
	return rise


## Knocks out of `s` what stands within `radius` m of `at` (the nearest
## half in crumbs), thrown along `push`, and cracks what is a little
## farther. Returns how many shards went.
static func smash(s: Structure, at: Vector3, radius: float, push: Vector3) -> int:
	var broken := 0
	for i in s.shards_near(at, radius * 1.5):
		if s.held[i] == 0:
			continue
		var off := s.centroid[i] - at
		var d := off.length()
		if d >= radius:
			s.strike(i, lerpf(0.7, Structure.CRACK, (d - radius) / (radius * 0.5)), push * 0.3)
			continue
		var away := push * randf_range(0.5, 1.0) + off * 2.0
		if d < radius * 0.5:
			s.shatter(i, away)
		else:
			s.blow(i, away)
		broken += 1
	return broken
