class_name Projectile
extends Node3D
## A plain ball shot at what is under the crosshair: a stand-in for whatever
## the real thing will be. It flies straight and stops at the first thing it
## touches.
## In a standing wall it knocks out what is around the point of impact and
## cracks what is a little farther; a loose piece is shoved; whoever can
## take a blow (the Brute) takes one; the ground only stops it.

## It stopped at `at`, on something facing `normal`, and knocked `torn`
## standing shards out.
signal landed(at: Vector3, normal: Vector3, torn: int)

const SPEED := 36.0  ## m/s
const RANGE := 80.0  ## m, then it is gone
const RADIUS := 0.1
## Standing shards centred this near (m) where it lands are knocked out: a
## hole a good metre across in a wall. The nearest half break into crumbs.
const HOLE := 0.7
## Farther, up to here (m), the bonds that hold them crack: hardest at the
## edge of the hole (CRACK_MOST, see Structure.strike), not at all at the end.
const CRACKS := 1.3
const CRACK_MOST := 0.7
## Speed (m/s) of what it knocks out, at most.
const THROW := 9.0
## Push given to a loose piece it hits (kg.m/s), and the most speed that is.
const PUNCH := 1200.0
const PUSH_MOST := 10.0
## Not drawn until it is this far from where it leaves (the middle of the
## character's chest): about where the hand that shoots is.
const SHOWN_FROM := 0.7
const TINT := Color(1.0, 0.55, 0.15)

static var _round: SphereMesh

var structure: Structure
var direction := Vector3.FORWARD
var flown := 0.0  ## m so far

var _ball: MeshInstance3D


## `at`: where it leaves from; `dir`: where to.
func setup(s: Structure, at: Vector3, dir: Vector3) -> void:
	structure = s
	position = at
	direction = dir.normalized()


func _ready() -> void:
	add_to_group("projectile")
	_ball = MeshInstance3D.new()
	_ball.mesh = _shape()
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.visible = false
	add_child(_ball)


## The ball, made once for every shot.
static func _shape() -> SphereMesh:
	if _round == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = TINT
		mat.emission_enabled = true
		mat.emission = TINT
		mat.emission_energy_multiplier = 0.6
		_round = SphereMesh.new()
		_round.radius = RADIUS
		_round.height = RADIUS * 2.0
		_round.radial_segments = 12
		_round.rings = 6
		_round.material = mat
	return _round


func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	var from := global_position
	var ray := PhysicsRayQueryParameters3D.create(
		from,
		from + direction * (step + RADIUS),
		Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS | Structure.LAYER_ACTOR
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		_land(hit["position"], hit["normal"], hit["rid"], hit["collider"])
		return
	global_position = from + direction * step
	flown += step
	_ball.visible = flown >= SHOWN_FROM
	if flown > RANGE:
		queue_free()


func _land(at: Vector3, normal: Vector3, rid: RID, what: Object) -> void:
	var s := structure
	var torn := 0
	if what is Brute:
		(what as Brute).fighter.take_hit(direction, 2, false)
	elif s != null:
		var piece := s.pieces.index_of(rid)
		if piece >= 0:
			var push := minf(PUNCH / s.pieces.mass[piece], PUSH_MOST)
			var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * push
			s.pieces.push(piece, direction * push, spin)
		elif s.owner_of(rid) > Pieces.NOT_OURS:
			var standing := s.held_count
			_break(at)
			torn = standing - s.held_count
	# (Shot from inside something, the ray gives no normal.)
	landed.emit(at, normal if normal.length_squared() > 0.5 else -direction, torn)
	queue_free()


## What stands around `at` is knocked out or cracked.
func _break(at: Vector3) -> void:
	var s := structure
	for i in s.shards_near(at, CRACKS):
		if s.held[i] == 0:
			continue
		var off := s.centroid[i] - at
		var d := off.length()
		if d >= HOLE:
			s.strike(i, lerpf(CRACK_MOST, Structure.CRACK, (d - HOLE) / (CRACKS - HOLE)), direction * 2.0)
			continue
		var away := direction * THROW * randf_range(0.4, 1.0) + off * 2.0
		if d < HOLE * 0.5:
			s.shatter(i, away)
		else:
			s.blow(i, away)
