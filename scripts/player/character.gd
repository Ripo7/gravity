class_name Character
extends Node3D
## A body you see: a mannequin and the tree that blends its clips. It
## decides nothing. Whoever owns it (the Player, a Brute) tells it how fast
## it goes, whether it is in the air, and when it jumps, lands,
## punches, kicks, guards, is hit or goes down; it turns that into a pose.
##
## Two sets of clips: the mannequin's own (Quaternius, CC0, assets/mannequin:
## standing, walking, jumping, flinching) and the fight (assets/fight, see
## SOURCE.md there): blows, the guard, being thrown and getting up made
## for games, by the same author on the same skeleton, and a kick that is
## motion capture.
##
## The tree, from the clips to the pose:
##
##   Idle ────────────────────────────┐
##   Walk ──pace──┐                   ├─ ground ─┐
##   Jog ───pace──┴─ walk_jog ─┐      │          │
##   Sprint ─pace──────────────┴ run ─┘          ├─ state ─ hold ─ pose
##   Jump_Start ─────────────────────────────────┤
##   Jump (in the air) ──────────────────────────┤
##   Jump_Land ──pace────────────────────────────┤
##   fight/hook, upswing, backhand, slam, kick ──┤
##   fight/guard (one pose) ─────────────────────┤
##   Hit_Chest, Hit_Head ────────────────────────┤
##   fight/thrown, fight/getup ──pace────────────┘
##
## Walk, jog and sprint are stretched to one common cycle so that the same
## foot is forward in all three, then mixed by speed; the cycle is the one
## at which the mixed stride covers the ground actually covered, so the feet
## do not slide.

## A strike starts: one of COMBO, or "kick".
signal swung(move: String)
## Its fist or foot is there: what is in the way takes it.
signal struck(move: String)

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
## Fighting. The blows the punch button chains, in order (then round
## again): a lunging hook, a swing up from the right, one back across from
## the left, and a leap that ends fist first on the ground. Each clip says
## when its fist is there, when the next move may start, how far it
## reaches and how hard it is (see tools/moves/build.py).
const COMBO: Array[String] = ["hook", "upswing", "backhand", "slam"]
## Steps of a sixtieth add up to a hair under the frame a clip says its
## blow lands on: this much (s) short still counts as there.
const LATE := 0.002
## The fists come up into the guard in this long (s), and down as fast.
const GUARD_UP := 0.1
## The bone the steps of the moves are given to.
const ROOT := "Rig/Skeleton3D:root"
## Getting up is played faster than it was made.
const UP_PACE := 1.3
## A blow taken shows as a flash of white (if it has its own colours, see
## `paint`) that fades over FLASH s.
const FLASH := 0.2
const FLASH_MOST := 0.7
## It also leans the body the way the blow goes, LEAN rad for a hard one,
## about its feet: it goes over at LEAN_IN of what is left to go a second
## (once the blow lets go of it, see `hold`) and comes back up at LEAN_BACK.
const LEAN := 0.32
const LEAN_IN := 30.0
const LEAN_BACK := 7.0
## Held still by a blow it takes (see `hold`), it trembles this much (m).
const TREMBLE := 0.025
## What the legs can be doing (see `state`), in the order of the tree's
## inputs.
const STATES: Array[String] = [
	"ground",
	"jump",
	"air",
	"land",
	"hook",
	"upswing",
	"backhand",
	"slam",
	"kick",
	"guard",
	"hit_chest",
	"hit_head",
	"blown",
	"up"
]
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
var _left := 0.0  # s before the state gives way to "ground" (0: it stays)
var _fade_back := 0.3  # s that takes
var _move_for := 0.0  # s of its clip the move under way has played
var _move_from := 0  # the physics step that took it up
var _move_out := false  # its fist or foot has been there
var _then := ""  # the move asked for next: "punch" or "kick"
var _guards := false  # the guard is asked for
var _tints: Array[BaseMaterial3D] = []  # its own colours, if it was painted
var _flash := 0.0  # how white it is (1 to 0)
var _held := 0.0  # s it stays frozen where it is
var _trembles := false  # while it does, it trembles
var _lean := Vector3.ZERO  # how it leans: the axis, as long as the angle (rad)
var _lean_more := Vector3.ZERO  # how much farther the blow it took still sends it


func _ready() -> void:
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.rotation.y = TURNED
	add_child(_model)
	_clips = _model.get_node("AnimationPlayer")
	_clips.add_animation_library("fight", load(MOVES) as AnimationLibrary)
	skeleton = _model.get_node("Rig/Skeleton3D")
	_skin = skeleton.get_node("Mannequin")
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
	tree.set("parameters/land_pace/scale", LAND_PACE)
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
## start of a jump. A move under way goes on: stepping off a heap of rubble
## does not cut a blow short.
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


## Is it doing something that keeps its feet where they are (a strike,
## which steps as it wants, or the guard)?
func busy() -> bool:
	return striking() or state == "guard"


## Are its fists up in front of it?
func guarding() -> bool:
	return state == "guard"


## Seconds before the fist or foot of the strike under way is there (0: it
## has been, or there is none).
func lands_in() -> float:
	if not striking() or _move_out:
		return 0.0
	return maxf(_about("hit") - _move_for, 0.0)


## How far from the body (m) the fist or foot of the strike under way is
## when it gets there, and how hard it is (2 a blow, 3 one that throws).
func reach() -> float:
	return _about("reach") if striking() else 0.0


func power() -> int:
	return int(_about("power")) if striking() else 0


## How high (m) that fist or foot is.
func height() -> float:
	return _about("height") if striking() else 0.0


## How far the clips carried the body in the last physics step (m, in the
## world): the steps the blows take.
func root_motion() -> Vector3:
	return skeleton.global_basis * tree.get_root_motion_position()


## Throws a blow: the first of COMBO from standing or from the guard.
## Asked for while one is under way, the next of COMBO follows it. Returns
## false if it cannot (in the air, or knocked down).
func punch() -> bool:
	return _ask("punch", COMBO[0])


## A kick: straight ahead with the right leg, stepping in.
func kick() -> bool:
	return _ask("kick", "kick")


## The guard, for as long as `on`: both fists up in front of the face,
## nothing else. It is taken up as soon as the body stands free (after the
## blow under way, if there is one) and let go at once.
func guard(on: bool) -> void:
	_guards = on
	if not on and state == "guard":
		_go("ground", GUARD_UP)


## Which way the fist or foot of the strike under way goes when it gets
## there (a unit vector, in this node's space: -Z is ahead).
func way() -> Vector3:
	if not striking():
		return Vector3.FORWARD
	# (The clips say it in the model's space, which looks along +Z.)
	return Vector3(-_about("way_x"), _about("way_y"), -_about("way_z"))


## It takes a blow: a `hard` one throws the head and chest back, another
## only shakes it. `going`: which way the blow goes (in the world); the
## body leans that way.
func hit(hard: bool, going := Vector3.ZERO) -> void:
	_flash = 1.0
	var clip := "Hit_Chest" if hard else "Hit_Head"
	_go(clip.to_lower(), 0.05, _clips.get_animation(clip).length, 0.2)
	var along := global_basis.inverse() * going
	along.y = 0.0
	if along.length() > 0.1:
		_lean_more = Vector3.UP.cross(along.normalized()) * (LEAN if hard else LEAN * 0.5)


## Frozen where it is for `seconds`: the instant a blow lands, on who
## throws it and on who takes it (`trembles`). From its next step: the
## pose of this one, in which the fist gets there, is still to come.
func hold(seconds: float, trembles := false) -> void:
	_held = maxf(_held, seconds)
	_trembles = trembles


func held() -> bool:
	return _held > 0.0


## Thrown off its feet: it goes over backwards, lands on its back and
## stays down.
func blown() -> void:
	_flash = 1.0
	_lean_more = Vector3.ZERO
	_go("blown", 0.08)


## It gets back on its feet. Returns how long that takes (s).
func up() -> float:
	var takes := _clips.get_animation("fight/getup").length / UP_PACE
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


func _physics_process(delta: float) -> void:
	if _held > 0.0:
		_held -= delta
		var out := Vector3(sin(_held * 190.0), 0.0, cos(_held * 230.0)) * TREMBLE
		_model.position = out if _trembles and _held > 0.0 else Vector3.ZERO
		_show_flash()
		tree.set("parameters/hold/scale", 0.0 if _held > 0.0 else 1.0)
		return
	if _lean != Vector3.ZERO or _lean_more != Vector3.ZERO:
		var goes := _lean_more * minf(LEAN_IN * delta, 1.0)
		_lean_more -= goes
		_lean = (_lean + goes) * exp(-LEAN_BACK * delta)
		if _lean.length() < 0.005 and _lean_more.length() < 0.005:
			_lean = Vector3.ZERO
			_lean_more = Vector3.ZERO
		_pose_lean()
	if striking():
		_move(delta)
	elif _guards and state == "ground":
		_go("guard", GUARD_UP)
	if _flash > 0.0:
		_flash = maxf(_flash - delta / FLASH, 0.0)
		_show_flash()
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_go("ground", _fade_back)


## A move is asked for: it starts now from standing or from the guard, or
## after the move under way (`then`: what to remember; `first`: what starts).
func _ask(then: String, first: String) -> bool:
	if striking():
		_then = then
		return true
	if state != "ground" and state != "guard" and state != "land":
		return false
	_start(first, 0.08)
	return true


func _start(named: String, fade: float) -> void:
	_move_for = 0.0
	# (Asked between two steps, by a key: the next one takes it up.)
	_move_from = Engine.get_physics_frames() + (0 if Engine.is_in_physics_frame() else 1)
	_move_out = false
	_then = ""
	_go(named, fade)
	if striking():
		swung.emit(named)


## What the clip of a move says about itself: "hit" (s before its fist or
## foot gets there), "next", "reach" (m), "power", "height" (m), "way_x",
## "way_y", "way_z". See MOVES.
func about(named: String, what: String) -> float:
	return _clips.get_animation("fight/" + named).get_meta(what, 0.0)


## Seconds before the fist or foot of the move `named` gets there.
func lands_after(named: String) -> float:
	return about(named, "hit")


func _about(what: String) -> float:
	return about(state, what)


## The move under way goes on: its fist or foot gets there, then the move
## asked for starts, or it stands again.
func _move(delta: float) -> void:
	# Its clip starts at the end of the step that takes the move up: nothing
	# of it plays in that one. (This count and the pose must agree to the
	# step: a fist can go a metre in one, and the blow counts on the pose in
	# which it is there.)
	if Engine.get_physics_frames() > _move_from:
		_move_for += delta
	if striking() and not _move_out and _move_for >= _about("hit") - LATE:
		_move_out = true
		struck.emit(state)
	var length := _clips.get_animation("fight/" + state).length
	var free := _about("next") if striking() else length
	if _then != "" and _move_for >= free:
		if _then == "punch":
			var k := COMBO.find(state)
			# After a blow, the next one; after anything else, the first.
			_start(COMBO[(k + 1) % COMBO.size()] if k >= 0 else COMBO[0], 0.12)
		else:
			_start(_then, 0.12)
	elif _move_for >= length:
		_go("ground", 0.25)


## Into state `to` over `fade` s. With `lasts`, it gives way to "ground"
## after that long, over `fade_back` s.
func _go(to: String, fade: float, lasts := 0.0, fade_back := 0.3) -> void:
	state = to
	_left = lasts
	_fade_back = fade_back
	(_node("state") as AnimationNodeTransition).xfade_time = fade
	tree.set("parameters/state/transition_request", to)


func _show_flash() -> void:
	for mat in _tints:
		mat.emission_energy_multiplier = _flash * FLASH_MOST


## The model, turned to look ahead and leaning as much as `_lean` says.
func _pose_lean() -> void:
	var angle := _lean.length()
	var tilt := Basis(_lean / angle, angle) if angle > 0.0 else Basis()
	_model.basis = tilt * Basis(Vector3.UP, TURNED)


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
	# Fighting: the blows and the guard.
	for named: String in COMBO + (["kick", "guard"] as Array[String]):
		t.add_node(named, _clip("fight/" + named))
	t.add_node("hit_chest", _clip("Hit_Chest"))
	t.add_node("hit_head", _clip("Hit_Head"))
	t.add_node("blown", _clip("fight/thrown"))
	_paced(t, "up", _clip("fight/getup"))
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
		"hook",
		"upswing",
		"backhand",
		"slam",
		"kick",
		"guard",
		"hit_chest",
		"hit_head",
		"blown",
		"up_pace"
	]
	for k in inputs.size():
		t.connect_node("state", k, inputs[k])
	# Everything behind one pace: 0 freezes the body where it is (`hold`).
	t.add_node("hold", AnimationNodeTimeScale.new())
	t.connect_node("hold", 0, "state")
	t.connect_node("output", 0, "hold")
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
