class_name Character
extends Node3D
## A body you see: a mannequin and the tree that blends its clips (both by
## Quaternius, CC0: see assets/mannequin). It decides nothing. Whoever owns
## it (the Player, a Dummy) tells it how fast it goes, whether it is in the
## air, and when it jumps, lands, shoots, punches, is hit or goes down; it
## turns that into a pose.
##
## The tree, from the clips to the pose:
##
##   Idle ────────────────────────────┐
##   Walk ──pace──┐                   ├─ ground ─┐
##   Jog ───pace──┴─ walk_jog ─┐      │          │
##   Sprint ─pace──────────────┴ run ─┘          ├─ state ─┐
##   Jump_Start ─────────────────────────────────┤         ├─ cast ─ pose
##   Jump (in the air) ──────────────────────────┤         │
##   Jump_Land ──pace────────────────────────────┤         │
##   Punch_Jab, Punch_Cross ──pace───────────────┤         │
##   Punch_Enter (its last pose: the guard) ─────┤         │
##   Hit_Chest, Hit_Head ────────────────────────┤         │
##   Death01, and the same backwards ──pace──────┘         │
##   Spell_Simple_Shoot (left arm only) ───────────────────┘
##
## Walk, jog and sprint are stretched to one common cycle so that the same
## foot is forward in all three, then mixed by speed; the cycle is the one
## at which the mixed stride covers the ground actually covered, so the feet
## do not slide.

## A punch starts (`strong`: a cross, with the right; else a jab).
signal swung(strong: bool)
## Its fist is out: what is there is hit.
signal struck(strong: bool)

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
## Fighting: the punches are played a little faster than the clips; the
## guard they end in is held GUARD_TIME s after the last one.
const PUNCH_PACE := 1.2
const GUARD_TIME := 0.9
## The moments of a punch, in seconds of its clip: the fist is out (the arm
## goes from the guard to straight in two frames just before), another
## punch may follow (the fist is on its way back), the fists are back up.
const JAB: Array[float] = [0.19, 0.4, 0.7]
const CROSS: Array[float] = [0.27, 0.55, 0.9]
## Getting up is the fall played backwards, faster.
const UP_PACE := 1.6
## A blow taken shows as a flash of white (if it has its own colours, see
## `paint`) that fades over FLASH s.
const FLASH := 0.2
const FLASH_MOST := 0.7
## What the legs can be doing (see `state`), in the order of the tree's
## inputs.
const STATES: Array[String] = [
	"ground", "jump", "air", "land", "jab", "cross", "guard", "hit_chest", "hit_head", "down", "up"
]
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

## One of STATES: what the body is doing.
var state := "ground"
var tree: AnimationTree
var skeleton: Skeleton3D

var _model: Node3D
var _skin: MeshInstance3D
var _clips: AnimationPlayer
var _walk_cycle := 1.0
var _jog_cycle := 1.0
var _sprint_cycle := 1.0
var _cast := 0.0  # how far out the arm is (0 to 1)
var _cast_left := 0.0  # s it stays out
var _left := 0.0  # s before the state gives way to "ground" (0: it stays)
var _fade_back := 0.3  # s that takes
var _punch_for := 0.0  # s of its clip the punch under way has played
var _punch_out := false  # its fist has been out
var _punch_again := false  # another one is asked for
var _tints: Array[BaseMaterial3D] = []  # its own colours, if it was painted
var _flash := 0.0  # how white it is (1 to 0)


func _ready() -> void:
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.rotation.y = TURNED
	add_child(_model)
	_clips = _model.get_node("AnimationPlayer")
	skeleton = _model.get_node("Rig/Skeleton3D")
	_skin = skeleton.get_node("Mannequin")
	_walk_cycle = _clips.get_animation("Walk").length
	_jog_cycle = _clips.get_animation("Jog_Fwd").length
	_sprint_cycle = _clips.get_animation("Sprint").length
	tree = AnimationTree.new()
	tree.tree_root = _build()
	_model.add_child(tree)
	tree.anim_player = tree.get_path_to(_clips)
	tree.active = true
	tree.set("parameters/land_pace/scale", LAND_PACE)
	tree.set("parameters/jab_pace/scale", PUNCH_PACE)
	tree.set("parameters/cross_pace/scale", PUNCH_PACE)
	tree.set("parameters/up_pace/scale", UP_PACE)
	move(0.0)


func _exit_tree() -> void:
	# Its own colours go before it does: left on, the renderer that stands in
	# when there is no screen (tests) looks for them once they are gone.
	for surface in _skin.get_surface_override_material_count():
		_skin.set_surface_override_material(surface, null)


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
	if state != "jump" and state != "air" and state != "down" and state != "up":
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


## Is a punch under way?
func punching() -> bool:
	return state == "jab" or state == "cross"


## Seconds before the fist of the punch under way is out (0: it has been).
func lands_in() -> float:
	if not punching() or _punch_out:
		return 0.0
	return maxf(_moments()[0] - _punch_for, 0.0) / PUNCH_PACE


## Throws a punch: a jab (left) from standing or from the guard, and while
## one is under way, the other hand is asked for next: jab, cross, jab...
## Each one ends in the guard. Returns false if it cannot (in the air, or
## knocked down).
func punch() -> bool:
	if punching():
		_punch_again = true
		return true
	if state != "ground" and state != "guard" and state != "land":
		return false
	_swing("jab")
	return true


## Fists down at once (the guard is left to walk away).
func relax() -> void:
	if state == "guard":
		_go("ground", 0.2)


## It takes a blow: a `hard` one throws the head and chest back, another
## only shakes it.
func hit(hard: bool) -> void:
	_flash = 1.0
	var clip := "Hit_Chest" if hard else "Hit_Head"
	_go(clip.to_lower(), 0.05, _clips.get_animation(clip).length, 0.2)


## It falls on its back and stays there.
func down() -> void:
	_flash = 1.0
	_go("down", 0.1)


## It gets back on its feet. Returns how long that takes (s).
func up() -> float:
	var takes := _clips.get_animation("Death01").length / UP_PACE
	_go("up", 0.1, takes, 0.25)
	return takes


## The two colours of the mannequin: its body and its joints. Painted, it
## also flashes when it takes a blow.
func paint(body: Color, joints: Color) -> void:
	var tints: Array[Color] = [body, joints]
	for surface in tints.size():
		var mat := (_skin.mesh.surface_get_material(surface) as BaseMaterial3D).duplicate() as BaseMaterial3D
		mat.albedo_color = tints[surface]
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = 0.0
		_skin.set_surface_override_material(surface, mat)
		_tints.append(mat)


## The arm that shoots goes out, whatever the legs are doing.
func shoot() -> void:
	_cast_left = CAST_HOLD
	tree.set("parameters/shoot_seek/seek_request", 0.0)


func _physics_process(delta: float) -> void:
	if punching():
		_punch(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta / FLASH, 0.0)
		for mat in _tints:
			mat.emission_energy_multiplier = _flash * FLASH_MOST
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_go("ground", _fade_back)
	_cast_left = maxf(_cast_left - delta, 0.0)
	var out := 1.0 if _cast_left > 0.0 else 0.0
	_cast = move_toward(_cast, out, delta / (CAST_IN if out > _cast else CAST_OUT))
	tree.set("parameters/cast/blend_amount", _cast)
	_model.rotation.y = TURNED - CAST_TURN * smoothstep(0.0, 1.0, _cast)


func _swing(kind: String) -> void:
	_punch_for = 0.0
	_punch_out = false
	_punch_again = false
	_go(kind, 0.08)
	swung.emit(kind == "cross")


func _moments() -> Array[float]:
	return CROSS if state == "cross" else JAB


## The punch under way goes on: its fist gets there, then the next punch
## starts if one was asked for, or the fists stay up for a while.
func _punch(delta: float) -> void:
	var moments := _moments()
	_punch_for += delta * PUNCH_PACE
	if not _punch_out and _punch_for >= moments[0]:
		_punch_out = true
		struck.emit(state == "cross")
	if _punch_again and _punch_for >= moments[1]:
		_swing("jab" if state == "cross" else "cross")
	elif _punch_for >= moments[2]:
		_go("guard", 0.12, GUARD_TIME, 0.35)


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
	var land_pace := AnimationNodeTimeScale.new()
	t.add_node("land_pace", land_pace)
	t.connect_node("land_pace", 0, "land")
	# Fighting: two punches, the guard they end in (the last pose of the clip
	# that goes into it), two blows taken, the fall and the same backwards.
	_paced(t, "jab", _clip("Punch_Jab"))
	_paced(t, "cross", _clip("Punch_Cross"))
	var fists_up := _clip("Punch_Enter")
	fists_up.use_custom_timeline = true
	fists_up.start_offset = _clips.get_animation("Punch_Enter").length - 0.02
	fists_up.timeline_length = 0.02
	fists_up.stretch_time_scale = false
	t.add_node("guard", fists_up)
	t.add_node("hit_chest", _clip("Hit_Chest"))
	t.add_node("hit_head", _clip("Hit_Head"))
	t.add_node("down", _clip("Death01"))
	var rise := _clip("Death01")
	rise.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	_paced(t, "up", rise)
	var body := AnimationNodeTransition.new()
	body.input_count = STATES.size()
	for k in STATES.size():
		body.set_input_name(k, STATES[k])
	body.set_input_reset(0, false)  # the gait is not started over
	body.allow_transition_to_self = true  # a second blow starts the flinch again
	body.set_input_as_auto_advance(1, true)  # the start of a jump runs into the air
	t.add_node("state", body)
	var inputs: Array[String] = [
		"ground",
		"jump_start",
		"air",
		"land_pace",
		"jab_pace",
		"cross_pace",
		"guard",
		"hit_chest",
		"hit_head",
		"down",
		"up_pace"
	]
	for k in inputs.size():
		t.connect_node("state", k, inputs[k])
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


## Clip `node` as `named`, behind a pace that can be set ("<named>_pace").
func _paced(t: AnimationNodeBlendTree, named: String, node: AnimationNodeAnimation) -> void:
	t.add_node(named, node)
	t.add_node(named + "_pace", AnimationNodeTimeScale.new())
	t.connect_node(named + "_pace", 0, named)


## A mix of two inputs that both keep running, so they stay in step.
func _mix(t: AnimationNodeBlendTree, named: String, from: String, to: String) -> void:
	var mix := AnimationNodeBlend2.new()
	mix.sync = true
	t.add_node(named, mix)
	t.connect_node(named, 0, from)
	t.connect_node(named, 1, to)
