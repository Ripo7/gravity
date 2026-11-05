class_name LevelRun
extends Node
## Flow of the sandbox: intro card -> play -> (crushed -> respawn) ... plus
## pause. No score, no callouts: the building is the show.

enum State { INTRO, PLAY, DOWN, PAUSED }

const RESPAWN_DELAY := 2.2

@export var world: GameWorld
@export var hud: Hud

var state := State.INTRO
var level: Level
## K.O.s this run (for scripted checks; never shown).
var deaths := 0

var _overlay: Control
var _state_before_pause := State.PLAY
var _was_captured := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not world.is_node_ready():
		await world.ready
	level = world.level
	if level == null or world.attract:
		hud.visible = false
		level = null
		return
	_overlay = Control.new()
	_overlay.theme = UiTheme.get_theme()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.get_parent().add_child(_overlay)
	if hud.touch:
		hud.add_pause_button(pause)
	world.player.died.connect(_on_died)
	world.player.damaged.connect(func(amount: float, from: Vector3) -> void: hud.hurt(amount, from))
	if Launch.options.get("mode", "") in ["showcase", "bench", "still", "probe", "play"]:
		_begin_play()  # scripted runs skip the card
	else:
		_show_intro()


# --- States -------------------------------------------------------------------


func _show_intro() -> void:
	state = State.INTRO
	world.player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := _panel()
	box.add_child(UiTheme.label(level.title, "TitleLabel"))
	if level.hint != "":
		var hint := UiTheme.label(level.hint)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 560
		box.add_child(hint)
	box.add_child(_spacer(6))
	box.add_child(UiTheme.label(_controls_text(), "SmallLabel"))
	box.add_child(_spacer(8))
	var start := UiTheme.button("Go", _begin_play)
	box.add_child(start)
	start.grab_focus()


func _controls_text() -> String:
	if hud.touch:
		return (
			"pouce gauche : bouger · glisser à droite : viser\n"
			+ "bouton violet : trou noir · bouton bouclier : bouclier · flèche : sauter"
		)
	return (
		"clic : trou noir · clic droit ou E : bouclier\n"
		+ "ZQSD bouger · Espace sauter · R tout reconstruire"
	)


func _begin_play() -> void:
	_clear_overlay()
	state = State.PLAY
	world.player.input_enabled = true
	if not hud.touch and not Launch.options.has("mode"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func pause() -> void:
	if state not in [State.PLAY, State.DOWN]:
		return
	_state_before_pause = state
	state = State.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := _panel()
	box.add_child(UiTheme.label("Pause", "TitleLabel"))
	box.add_child(_spacer(6))
	var resume := UiTheme.button("Reprendre", _resume)
	box.add_child(resume)
	box.add_child(UiTheme.button("Tout reconstruire", _restart))
	box.add_child(UiTheme.button("Menu", GameState.go_to_menu))
	resume.grab_focus()


func _resume() -> void:
	_clear_overlay()
	get_tree().paused = false
	state = _state_before_pause
	if not hud.touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _restart() -> void:
	world.reset()


## Crushed: a short K.O., then back at the start. The world stays broken.
func _on_died() -> void:
	if state != State.PLAY:
		return
	state = State.DOWN
	deaths += 1
	Sfx.ui("death", -2.0)
	hud.popup("K.O.", Color(0.85, 0.1, 0.2), 72)
	await get_tree().create_timer(RESPAWN_DELAY, true, false, true).timeout
	if not is_inside_tree():
		return
	world.player.respawn()
	world.player.input_enabled = true
	if state == State.DOWN:
		state = State.PLAY
	elif state == State.PAUSED:
		_state_before_pause = State.PLAY


# --- Frame -----------------------------------------------------------------------


func _process(_delta: float) -> void:
	if level == null:
		return
	if Input.is_action_just_pressed("reset_arena") and state != State.PAUSED:
		_restart()
		return
	match state:
		State.PLAY, State.DOWN:
			# Browsers drop pointer lock on Esc without sending the key.
			var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			if (_was_captured and not captured) or Input.is_action_just_pressed("release_mouse"):
				pause()
				return
			_was_captured = captured
		State.PAUSED:
			if Input.is_action_just_pressed("release_mouse"):
				_resume()


# --- UI helpers -------------------------------------------------------------------


func _panel() -> VBoxContainer:
	_clear_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.95, 0.95, 0.97, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	return box


func _clear_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
