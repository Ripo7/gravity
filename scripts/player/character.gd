class_name Character
extends Node3D
## The body you see: a mannequin and the tree that blends its clips (both by
## Quaternius, CC0: see assets/mannequin). It decides nothing. The Player
## tells it how fast it goes, whether it is in the air, and when it jumps,
## lands or shoots; it turns that into a pose.
##
## The tree, from the clips to the pose:
##
##   Idle ────────────────────────────┐
##   Walk ──pace──┐                   ├─ ground ─┐
##   Jog ───pace──┴─ walk_jog ─┐      │          │
##   Sprint ─pace──────────────┴ run ─┘          ├─ state ─┐
##   Jump_Start ─────────────────────────────────┤         ├─ cast ─ pose
##   Jump (in the air) ──────────────────────────┤         │
##   Jump_Land ──pace────────────────────────────┘         │
##   Spell_Simple_Shoot (left arm only) ───────────────────┘
##
## Walk, jog and sprint are stretched to one common cycle so that the same
## foot is forward in all three, then mixed by speed; the cycle is the one
## at which the mixed stride covers the ground actually covered, so the feet
## do not slide.

const SCENE := "res://assets/mannequin/AnimationLibrary_Godot_Standard.gltf"
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
## Shooting: the left arm (the one the clip raises) goes out over CAST_IN s,
## stays CAST_HOLD s after the last shot and comes back over CAST_OUT s.
const CAST_IN := 0.07
const CAST_HOLD := 0.4
const CAST_OUT := 0.3
const BONE := "Rig/Skeleton3D:DEF-%s"
const CAST_BONES: Array[String] = [
	"spine.002", "spine.003", "shoulder.L", "upper_arm.L", "forearm.L", "hand.L"
]
## In the clip the whole body is turned from the hips, the left shoulder
## forward; the hips cannot be taken from it (the legs hang from them), so
## the body is turned this much (rad) instead, or the arm would point off to
## the left of what is shot at.
const CAST_TURN := 0.5
const FINGERS: Array[String] = ["f_index", "f_middle", "f_ring", "f_pinky", "thumb"]

## "ground", "jump", "air" or "land": what the legs are doing.
var state := "ground"
var tree: AnimationTree
var skeleton: Skeleton3D

var _model: Node3D
var _clips: AnimationPlayer
var _walk_cycle := 1.0
var _jog_cycle := 1.0
var _sprint_cycle := 1.0
var _cast := 0.0  # how far out the arm is (0 to 1)
var _cast_left := 0.0  # s it stays out
var _land_left := 0.0
var _state_for := 0.0  # s in the current state


func _ready() -> void:
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.rotation.y = TURNED
	add_child(_model)
	_clips = _model.get_node("AnimationPlayer")
	skeleton = _model.get_node("Rig/Skeleton3D")
	_walk_cycle = _clips.get_animation("Walk").length
	_jog_cycle = _clips.get_animation("Jog_Fwd").length
	_sprint_cycle = _clips.get_animation("Sprint").length
	tree = AnimationTree.new()
	tree.tree_root = _build()
	_model.add_child(tree)
	tree.anim_player = tree.get_path_to(_clips)
	tree.active = true
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
## start of a jump.
func fall() -> void:
	if state == "ground" or state == "land":
		_go("air", 0.2)


## Back on the ground, having come down at `down` m/s while going `along`
## m/s over the ground.
func land(down: float, along: float) -> void:
	if state == "ground" or state == "land":
		return
	if down > LAND_HARD or along < LAND_STILL:
		_land_left = LAND_TIME
		_go("land", 0.06)
	else:
		_go("ground", 0.15)


## The arm that shoots goes out, whatever the legs are doing.
func shoot() -> void:
	_cast_left = CAST_HOLD
	tree.set("parameters/shoot_seek/seek_request", 0.0)


func _physics_process(delta: float) -> void:
	_state_for += delta
	if state == "land":
		_land_left -= delta
		if _land_left <= 0.0:
			_go("ground", 0.3)
	_cast_left = maxf(_cast_left - delta, 0.0)
	var out := 1.0 if _cast_left > 0.0 else 0.0
	_cast = move_toward(_cast, out, delta / (CAST_IN if out > _cast else CAST_OUT))
	tree.set("parameters/cast/blend_amount", _cast)
	_model.rotation.y = TURNED - CAST_TURN * smoothstep(0.0, 1.0, _cast)


func _go(to: String, fade: float) -> void:
	state = to
	_state_for = 0.0
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
	var land_pace := AnimationNodeTimeScale.new()
	t.add_node("land_pace", land_pace)
	t.connect_node("land_pace", 0, "land")
	var legs := AnimationNodeTransition.new()
	legs.input_count = 4
	var states: Array[String] = ["ground", "jump", "air", "land"]
	for k in states.size():
		legs.set_input_name(k, states[k])
	legs.set_input_reset(0, false)  # the gait is not started over
	legs.set_input_as_auto_advance(1, true)  # the start of a jump runs into the air
	t.add_node("state", legs)
	t.connect_node("state", 0, "ground")
	t.connect_node("state", 1, "jump_start")
	t.connect_node("state", 2, "air")
	t.connect_node("state", 3, "land_pace")
	# The arm that shoots, over whatever the rest does.
	t.add_node("shoot", _clip("Spell_Simple_Shoot"))
	t.add_node("shoot_seek", AnimationNodeTimeSeek.new())
	t.connect_node("shoot_seek", 0, "shoot")
	var cast := AnimationNodeBlend2.new()
	cast.filter_enabled = true
	for bone in CAST_BONES:
		cast.set_filter_path(NodePath(BONE % bone), true)
	for finger in FINGERS:
		for joint in 3:
			cast.set_filter_path(NodePath(BONE % ("%s.0%d.L" % [finger, joint + 1])), true)
	t.add_node("cast", cast)
	t.connect_node("cast", 0, "state")
	t.connect_node("cast", 1, "shoot_seek")
	t.connect_node("output", 0, "cast")
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
