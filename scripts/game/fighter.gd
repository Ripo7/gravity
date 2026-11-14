class_name Fighter
extends RefCounted
## What the two brutes have in common: what their blows do, to each other
## and to what stands, and what happens to one that is knocked off its
## feet. It flies, goes through whatever is in its way, lands, lies there
## a moment and gets up.
##
## Each brute (the Player, the Brute) is a body with a Character, a
## `facing` and one of these, called `fighter`, and is in GROUP.

## A blow lands, is taken, or breaks what stands: how hard it jolts whoever
## watches from behind this brute (0 to 1; the player's camera shakes).
signal jolted(amount: float)

const GROUP := "fighter"
## A fist is on the other when it is CONTACT m from its axis; a strike
## that would stop short carries its owner there, at LUNGE m/s at most. It
## counts if the fist is no more than SLACK m short and the other no more
## than WIDE m to either side.
const CONTACT := 0.22
const SLACK := 0.25
const WIDE := 0.5
const LUNGE := 5.0
## The moves that send who takes them flying (the blow from overhead that
## ends the combination, the kick), at THROW m/s along the ground and LIFT
## up. The others push it SHOVE m/s for each point of power, the way the
## fist goes (and half as much away from who throws it).
const LAUNCHERS: Array[String] = ["slam", "kick"]
const THROW := 12.0
const LIFT := 4.0
const SHOVE := 2.5
## The instant a blow lands, both brutes are held still: this long (s), by
## power. And what it jolts: who lands it, who takes it, and a blow that
## only breaks what stands.
const STOP: Array[float] = [0.0, 0.05, 0.07, 0.12]
const JOLT_GIVEN: Array[float] = [0.0, 0.35, 0.5, 0.75]
const JOLT_TAKEN: Array[float] = [0.0, 0.4, 0.6, 1.0]
const JOLT_WALL := 0.25
## A blow that meets a guard (see `take_hit`): it only pushes who holds it,
## this fast (m/s) for each point of power, and jolts it this much.
const BLOCKED := 1.0
const JOLT_BLOCKED := 0.3
## A guard stops what comes from in front: from no more than this (rad)
## off the way its holder faces.
const GUARD_WIDE := 1.2
## What a fist or a foot knocks out of what stands: within this radius
## (m), by power (2 a blow, 3 one that throws).
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
## A brute stopped STUCK s by what stands on its way goes through it: what
## is within BREACH m of two points in front of it, at its knees and at its
## shoulders (BREACH_AT, m up), is knocked out (see `breach`).
const STUCK := 0.35
const BREACH := 0.9
const BREACH_AT: Array[float] = [0.6, 1.5]
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
	# A piece that goes off under its feet does not take it along (its
	# speed would be added to a throw).
	of.platform_floor_layers = 0
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
	var going := Basis(Vector3.UP, facing) * character.way()
	var landed := false
	for node in body.get_tree().get_nodes_in_group(GROUP):
		if node == body:
			continue
		var d: Vector3 = node.global_position - body.global_position
		var along := d.dot(ahead)
		if absf(d.y) < 1.0 and along > 0.0 and along < reach + CONTACT + SLACK:
			if absf(d.cross(ahead).y) < WIDE:
				var other := node.get("fighter") as Fighter
				if other.take_hit(ahead, power, move in LAUNCHERS, going):
					landed = true
	var broken := 0
	if structure != null:
		# Where the fist ends up, or the first standing thing on its way there
		# (a blow that lunges reaches past a wall the body is stopped by).
		var from := body.global_position + Vector3.UP * height
		var at := from + ahead * (reach + 0.1)
		var mask := Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
		var met := body.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, at, mask)
		)
		if not met.is_empty():
			at = met["position"]
		_scatter(at, HOLE[power], ahead, RUBBLE * power)
		clear(ahead, RUBBLE * power)
		broken = smash(structure, at, HOLE[power], ahead * 6.0)
	if landed:
		character.hold(STOP[power])
		jolted.emit(JOLT_GIVEN[power])
	elif broken > 0:
		jolted.emit(JOLT_WALL)


## A blow from a brute that faces along `way`, of `power`, its fist going
## along `going` (along `way` if nothing is said). `thrown`: it sends the
## body flying. Returns false if it does not reach it (off its feet
## already). A body that holds its guard towards the blow blocks it,
## whatever the blow: it keeps its feet and its guard, and gives a little
## ground.
func take_hit(way: Vector3, power: int, thrown: bool, going := Vector3.ZERO) -> bool:
	if state != "up":
		return false
	var flat := Vector3(way.x, 0, way.z).normalized()
	if blocks(flat):
		body.velocity += flat * BLOCKED * power
		character.hold(STOP[1], true)
		jolted.emit(JOLT_BLOCKED)
		return true
	if thrown:
		launch(flat * THROW + Vector3.UP * LIFT)
	else:
		var pushed := (Vector3(going.x, 0, going.z) + flat * 0.5).normalized()
		character.hit(power > 1, pushed)
		body.velocity += pushed * SHOVE * power
	character.hold(STOP[power], true)
	jolted.emit(JOLT_TAKEN[power])
	return true


## Would its guard stop a blow that goes along `way` (flat)? It is up, and
## turned towards where the blow comes from.
func blocks(way: Vector3) -> bool:
	if not character.guarding():
		return false
	var facing: float = body.get("facing")
	return (Basis(Vector3.UP, facing) * Vector3.FORWARD).angle_to(-way) < GUARD_WIDE


## Held still by a blow that has just landed: nothing moves it meanwhile.
func held() -> bool:
	return character.held()


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


## Goes through what stands in front of it, on the side of `ahead`: a hole
## its size, and the rubble out of the way.
func breach(ahead: Vector3) -> void:
	if structure == null:
		return
	for height: float in BREACH_AT:
		var at := body.global_position + ahead * 0.8 + Vector3.UP * height
		Fighter.smash(structure, at, BREACH, ahead * 5.0)
	# And what it is up against: the edge of a hole too small holds it too.
	for k in body.get_slide_collision_count():
		var touched := body.get_slide_collision(k)
		var i := structure.owner_of(touched.get_collider_rid())
		if i >= 0 and structure.held[i] == 1 and touched.get_normal().y < 0.7:
			structure.blow(i, ahead * 5.0)
	clear(ahead, RUBBLE * 3.0)


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


## The speed over the ground (m/s) of `of` during a blow: where the
## move itself steps, fitted to `opponent` until the blow lands. A strike
## that would stop short is carried onto it by the time its fist or foot
## gets there; one whose own steps would take it past (some dash a long
## way in) is held back, so that the fist lands on the other and not
## behind it.
static func move_speed(of: Node3D, with: Character, opponent: Node3D, delta: float) -> Vector3:
	var steps := with.root_motion() / delta
	steps.y = 0.0
	var lands_in := with.lands_in()
	if not is_instance_valid(opponent) or lands_in <= 0.0:
		return steps
	var d := opponent.global_position - of.global_position
	d.y = 0.0
	var gap := d.length() - with.reach() - CONTACT
	var towards := d.normalized()
	var closing := steps.dot(towards)
	var needed := minf(gap / maxf(lands_in, delta), LUNGE)
	var fitted := clampf(maxf(closing, needed), 0.0, maxf(gap, 0.0) / delta)
	return steps + towards * (fitted - closing)


## Stopped by something low while going along `wish` (a unit vector, on
## the ground): `of` steps up onto it, if it is no higher than `height` m and
## there is room. Returns how much it rose (m).
static func climb(of: CharacterBody3D, wish: Vector3, stride: float, height: float) -> float:
	if not of.is_on_floor():
		return 0.0
	var blocked := false
	for k in of.get_slide_collision_count():
		var n := of.get_slide_collision(k).get_normal()
		# (Anything it cannot walk up: a face steeper than a floor too.)
		if n.y > -0.5 and n.y < 0.7 and n.dot(wish) < -0.3:
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
