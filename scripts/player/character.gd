class_name Character
extends Node3D
## A body you see: a mannequin and the tree that blends its clips. It
## decides nothing. Whoever owns it (the Player) tells it how fast it goes,
## whether it is in the air, and when it jumps, lands, punches or kicks; it
## turns that into a pose, and says when a fist or a foot gets there.
##
## Two sets of clips: the mannequin's own (Quaternius, CC0, assets/mannequin:
## standing, walking, jumping) and the blows (assets/fight, see SOURCE.md
## there): made for games, by the same author on the same skeleton, and a
## kick that is motion capture.
##
## The tree, from the clips to the pose:
##
##   Idle ────────────────────────────┐
##   Walk ──pace──┐                   ├─ ground ─┐
##   Jog ───pace──┴─ walk_jog ─┐      │          │
##   Sprint ─pace──────────────┴ run ─┘          ├─ state ─ pose
##   Jump_Start ─────────────────────────────────┤
##   Jump (in the air) ──────────────────────────┤
##   Jump_Land ──pace────────────────────────────┤
##   fight/jab, cross, slam, kick ───────────────┘
##
## Walk, jog and sprint are stretched to one common cycle so that the same
## foot is forward in all three, then mixed by speed; the cycle is the one
## at which the mixed stride covers the ground actually covered, so the feet
## do not slide.

## A strike starts: one of COMBO, or "kick".
signal swung(move: String)
## The fist or foot of the strike under way is thrown: `limb` is where it
## is drawn in this step (see limb()). `there`: this is the pose in which
## its clip has it land. Said every step from SWING before that pose to
## that pose, or until the blow has landed (see landed()).
signal reached(limb: PackedVector3Array, there: bool)
## The clip of the strike under way has its fist or foot there.
signal struck(move: String)
## The pose of this step of a strike is set (said before `reached`).
signal posed

const SCENE := "res://assets/mannequin/AnimationLibrary_Godot_Standard.gltf"
const MOVES := "res://assets/fight/moves.tres"
## The model looks along +Z; this node looks along -Z like everything else.
const TURNED := PI
## Ground speed (m/s) at which the feet of each clip do not slide, measured
## on the clips (see README), and the length of their cycles (s).
const WALK_PACE := 1.05
const JOG_PACE := 5.2
const SPRINT_PACE := 7.8
## Down to this share of the walk's pace, the walk is only slowed down;
## slower still, its steps get shorter too.
const SLOW_WALK := 0.6
## Jump_Start opens with a crouch; a jump must leave at once, so it is
## entered here (s).
const JUMP_FROM := 0.12
## Landing: the clip crouches deep and takes its time; it is played faster,
## and only when the fall or the standstill calls for it (see land()).
const LAND_PACE := 1.5
const LAND_HARD := 8.5  ## m/s down: a landing this hard is always shown
const LAND_STILL := 1.5  ## m/s along the ground: slower than this, it is shown too
const LAND_TIME := 0.5  ## s before the legs go back to standing or running
## The blows the punch button chains, in order (then round again): a
## straight left and a straight right thrown standing, the fists at the
## height of the shoulder, and a leap that ends fist first on the ground.
## Each clip says when its fist is there, when the next move may start,
## how far it reaches, how hard it is and with which hand it is thrown
## (see tools/moves/build.py).
const COMBO: Array[String] = ["jab", "cross", "slam"]
## Steps of a sixtieth add up to a hair under the frame a clip says its
## blow lands on: this much (s) short still counts as there.
const LATE := 0.002
## A fist or a foot is thrown this long (s) before its clip has it land:
## from then on, what it touches takes the blow.
const SWING := 0.1
## The limbs that strike, from the body out: where the limb leaves the
## body, its middle joint, and what lands (the knuckles, the toes).
const ARM: Array[String] = ["DEF-upper_arm.R", "DEF-forearm.R", "DEF-f_middle.01.R"]
const ARM_LEFT: Array[String] = ["DEF-upper_arm.L", "DEF-forearm.L", "DEF-f_middle.01.L"]
const LEG: Array[String] = ["DEF-thigh.R", "DEF-shin.R", "DEF-toe.R"]
## The rest of the body, which goes into nothing that stands: its parts
## (bones), and how far round its bone each reaches (m). Not the forearm
## and fist that strike; in a kick, not the right leg below the hip.
const BULK := {
	"DEF-head": 0.16,
	"DEF-spine.003": 0.2,
	"DEF-upper_arm.L": 0.1,
	"DEF-upper_arm.R": 0.1,
	"DEF-hand.L": 0.06,
	"DEF-hand.R": 0.06,
	"DEF-shin.L": 0.08,
	"DEF-toe.L": 0.05,
	"DEF-shin.R": 0.08,
	"DEF-toe.R": 0.05,
}
## The bone the steps of the moves are given to.
const ROOT := "Rig/Skeleton3D:root"
## What the body can be doing (see `state`), in the order of the tree's
## inputs.
const STATES: Array[String] = ["ground", "jump", "air", "land", "jab", "cross", "slam", "kick"]
## One of STATES: what the body is doing.
var state := "ground"
var tree: AnimationTree
var skeleton: Skeleton3D

var _model: Node3D
var _clips: AnimationPlayer
var _walk_cycle := 1.0
var _jog_cycle := 1.0
var _sprint_cycle := 1.0
var _left := 0.0  # s before the state gives way to "ground" (0: it stays)
var _fade_back := 0.3  # s that takes
var _move_for := 0.0  # s of its clip the move under way has played
var _move_from := 0  # the physics step that took it up
var _move_out := false  # its clip has had its fist or foot there
var _spent := false  # its blow has landed, or has had its time
var _arm := PackedInt32Array()  # the bones of ARM
var _arm_left := PackedInt32Array()
var _leg := PackedInt32Array()
var _bulk := PackedInt32Array()  # the bones of BULK
var _then := ""  # the move asked for next: "punch" or "kick"


func _ready() -> void:
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.rotation.y = TURNED
	add_child(_model)
	_clips = _model.get_node("AnimationPlayer")
	_clips.add_animation_library("fight", load(MOVES) as AnimationLibrary)
	skeleton = _model.get_node("Rig/Skeleton3D")
	_walk_cycle = _clips.get_animation("Walk").length
	_jog_cycle = _clips.get_animation("Jog_Fwd").length
	_sprint_cycle = _clips.get_animation("Sprint").length
	tree = AnimationTree.new()
	tree.tree_root = _build()
	_model.add_child(tree)
	tree.anim_player = tree.get_path_to(_clips)
	# With the physics, so that the steps of a move reach the body that takes
	# them at the same pace.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.root_motion_track = NodePath(ROOT)
	tree.active = true
	# The pose of a step is set after this node has had its turn in it:
	# where a limb is drawn is read then.
	tree.mixer_applied.connect(_posed)
	for bone in ARM:
		_arm.append(skeleton.find_bone(bone))
	for bone in LEG:
		_leg.append(skeleton.find_bone(bone))
	for bone in ARM_LEFT:
		_arm_left.append(skeleton.find_bone(bone))
	for bone: String in BULK:
		_bulk.append(skeleton.find_bone(bone))
	tree.set("parameters/land_pace/scale", LAND_PACE)
	move(0.0)


## The speed along the ground (m/s) the legs must show.
func move(speed: float) -> void:
	# Below a slow walk, the walk fades into standing: shorter steps. Then
	# walk to jog, jog to sprint.
	var steps := clampf(speed / (WALK_PACE * SLOW_WALK), 0.0, 1.0)
	var jog := clampf((speed - WALK_PACE) / (JOG_PACE - WALK_PACE), 0.0, 1.0)
	var sprint := clampf((speed - JOG_PACE) / (SPRINT_PACE - JOG_PACE), 0.0, 1.0)
	# The stride of the mix (m), and the cycle that makes it cover `speed`.
	var stride := lerpf(WALK_PACE * _walk_cycle, JOG_PACE * _jog_cycle, jog)
	stride = lerpf(stride, SPRINT_PACE * _sprint_cycle, sprint) * steps
	var cycle := _walk_cycle / SLOW_WALK if speed < 0.01 else minf(stride / speed, _walk_cycle / SLOW_WALK)
	tree.set("parameters/walk_pace/scale", _walk_cycle / cycle)
	tree.set("parameters/jog_pace/scale", _jog_cycle / cycle)
	tree.set("parameters/sprint_pace/scale", _sprint_cycle / cycle)
	tree.set("parameters/walk_jog/blend_amount", jog)
	tree.set("parameters/run/blend_amount", sprint)
	tree.set("parameters/ground/blend_amount", steps)


## The feet leave the ground for a jump.
func jump() -> void:
	_go("jump", 0.08)


## In the air without having jumped (off an edge), or still there after the
## start of a jump. A move under way goes on: stepping off an edge does not
## cut a blow short.
func fall() -> void:
	if state != "jump" and state != "air" and not striking():
		_go("air", 0.2)


## Back on the ground, having come down at `down` m/s while going `along`
## m/s over the ground.
func land(down: float, along: float) -> void:
	if state != "jump" and state != "air":
		return
	if down > LAND_HARD or along < LAND_STILL:
		_go("land", 0.06, LAND_TIME, 0.3)
	else:
		_go("ground", 0.15)


## Is a punch or a kick under way?
func striking() -> bool:
	return state == "kick" or state in COMBO


## How far from the body (m) the fist or foot of the strike under way is
## when it gets there, and how hard it is (2 a blow, 3 a heavy one).
func reach() -> float:
	return _about("reach") if striking() else 0.0


func power() -> int:
	return int(_about("power")) if striking() else 0


## How high (m) that fist or foot is.
func height() -> float:
	return _about("height") if striking() else 0.0


## The limb that strikes in the move under way, where it is drawn now (in
## the world): where it leaves the body (the shoulder, the hip), its middle
## joint (the elbow, the knee) and what lands (the knuckles, the toes).
func limb() -> PackedVector3Array:
	var at := PackedVector3Array()
	var bones := _leg if state == "kick" else (_arm_left if _with_left() else _arm)
	for bone in bones:
		at.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
	return at


## The body but for the limb that strikes in the move under way: where
## each part of BULK is drawn now (x, y, z, in the world) and how far
## round that it reaches (w).
func bulk() -> PackedVector4Array:
	var parts := PackedVector4Array()
	var k := 0
	for bone: String in BULK:
		# (Not the hand that strikes, nor the leg that kicks.)
		var strikes := (
			bone in LEG if state == "kick" else bone == ("DEF-hand.L" if _with_left() else "DEF-hand.R")
		)
		if not strikes:
			var at := skeleton.global_transform * skeleton.get_bone_global_pose(_bulk[k]).origin
			parts.append(Vector4(at.x, at.y, at.z, BULK[bone]))
		k += 1
	return parts


## Is the strike under way thrown with the left hand?
func _with_left() -> bool:
	return striking() and _about("left") > 0.5


## The blow of the strike under way has landed: it lands no more.
func landed() -> void:
	_spent = true


## How far the clips carried the body in the last physics step (m, in the
## world): the steps the blows take.
func root_motion() -> Vector3:
	return skeleton.global_basis * tree.get_root_motion_position()


## Throws a blow: the first of COMBO from standing. Asked for while one
## is under way, the next of COMBO follows. Returns false if it
## cannot (in the air).
func punch() -> bool:
	return _ask("punch", COMBO[0])


## A kick: straight ahead with the right leg, stepping in.
func kick() -> bool:
	return _ask("kick", "kick")


func _physics_process(delta: float) -> void:
	if striking():
		_move(delta)
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_go("ground", _fade_back)


## A move is asked for: it starts now from standing, or after the move
## under way (`then`: what to remember; `first`: what starts).
func _ask(then: String, first: String) -> bool:
	if striking():
		_then = then
		return true
	if state != "ground" and state != "land":
		return false
	_start(first, 0.08)
	return true


func _start(named: String, fade: float) -> void:
	_move_for = 0.0
	# (Asked between two steps, by a key: the next one takes it up.)
	_move_from = Engine.get_physics_frames() + (0 if Engine.is_in_physics_frame() else 1)
	_move_out = false
	_spent = false
	_then = ""
	_go(named, fade)
	swung.emit(named)


## What the clip of the move under way says about itself: "hit" (s before
## its fist or foot gets there), "next", "reach" (m), "power", "height"
## (m). See MOVES.
func _about(what: String) -> float:
	return _clips.get_animation("fight/" + state).get_meta(what, 0.0)


## The move under way goes on: its fist or foot gets there, then the move
## asked for starts, or it stands again.
func _move(delta: float) -> void:
	# Its clip starts at the end of the step that takes the move up: nothing
	# of it plays in that one. (This count and the pose must agree to the
	# step: a fist can go a metre in one, and the blow counts on the pose in
	# which it is there.)
	if Engine.get_physics_frames() > _move_from:
		_move_for += delta
	if not _move_out and _move_for >= _about("hit") - LATE:
		_move_out = true
		struck.emit(state)
	var length := _clips.get_animation("fight/" + state).length
	if _then != "" and _move_for >= _about("next"):
		if _then == "punch":
			var k := COMBO.find(state)
			# After a blow, the next one; after a kick, the first.
			_start(COMBO[(k + 1) % COMBO.size()] if k >= 0 else COMBO[0], 0.12)
		else:
			_start(_then, 0.12)
	elif _move_for >= length:
		_go("ground", 0.25)


## The pose of this step is set. While a fist or a foot is thrown, says
## where it is.
func _posed() -> void:
	if not striking():
		return
	posed.emit()
	if _spent or _move_for < _about("hit") - SWING - LATE:
		return
	# (Its last say is in the pose in which the clip has it land.)
	_spent = _move_out
	reached.emit(limb(), _move_out)


## Into state `to` over `fade` s. With `lasts`, it gives way to "ground"
## after that long, over `fade_back` s.
func _go(to: String, fade: float, lasts := 0.0, fade_back := 0.3) -> void:
	state = to
	_left = lasts
	_fade_back = fade_back
	(_node("state") as AnimationNodeTransition).xfade_time = fade
	tree.set("parameters/state/transition_request", to)


func _node(named: String) -> AnimationNode:
	return (tree.tree_root as AnimationNodeBlendTree).get_node(named)


func _build() -> AnimationNodeBlendTree:
	var t := AnimationNodeBlendTree.new()
	# The ground: standing, walking, jogging, sprinting.
	t.add_node("idle", _clip("Idle"))
	for gait: Array in [["walk", "Walk"], ["jog", "Jog_Fwd"], ["sprint", "Sprint"]]:
		t.add_node(gait[0], _clip(gait[1]))
		t.add_node(gait[0] + "_pace", AnimationNodeTimeScale.new())
		t.connect_node(gait[0] + "_pace", 0, gait[0])
	_mix(t, "walk_jog", "walk_pace", "jog_pace")
	_mix(t, "run", "walk_jog", "sprint_pace")
	_mix(t, "ground", "idle", "run")
	# The air.
	var start := _clip("Jump_Start")
	start.use_custom_timeline = true
	start.start_offset = JUMP_FROM
	start.timeline_length = _clips.get_animation("Jump_Start").length - JUMP_FROM
	start.stretch_time_scale = false
	t.add_node("jump_start", start)
	t.add_node("air", _clip("Jump"))
	t.add_node("land", _clip("Jump_Land"))
	t.add_node("land_pace", AnimationNodeTimeScale.new())
	t.connect_node("land_pace", 0, "land")
	# The blows.
	for named: String in COMBO + (["kick"] as Array[String]):
		t.add_node(named, _clip("fight/" + named))
	var body := AnimationNodeTransition.new()
	body.input_count = STATES.size()
	for k in STATES.size():
		body.set_input_name(k, STATES[k])
	body.set_input_reset(0, false)  # the gait is not started over
	body.allow_transition_to_self = true  # a second kick starts its clip again
	body.set_input_as_auto_advance(1, true)  # the start of a jump runs into the air
	t.add_node("state", body)
	var inputs: Array[String] = ["ground", "jump_start", "air", "land_pace", "jab", "cross", "slam", "kick"]
	for k in inputs.size():
		t.connect_node("state", k, inputs[k])
	t.connect_node("output", 0, "state")
	return t


func _clip(named: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = named
	return node


## A mix of two inputs that both keep running, so they stay in step.
func _mix(t: AnimationNodeBlendTree, named: String, from: String, to: String) -> void:
	var mix := AnimationNodeBlend2.new()
	mix.sync = true
	t.add_node(named, mix)
	t.connect_node(named, 0, from)
	t.connect_node(named, 1, to)
