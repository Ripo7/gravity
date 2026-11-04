class_name LevelRun
extends Node
## Flow of one level (time attack): intro card -> play (clock running) ->
## cleared or dead -> results. Also pause, and callouts for the HUD.

signal finished(cleared: bool, stars: int, seconds: float)

enum State { INTRO, PLAY, CLEARED, DEAD, RESULT, PAUSED }

const CHAIN_WINDOW := 1.4
const RESULT_DELAY := 1.6  ## seconds of watching the collapse before results
const SANDBOX_RESPAWN := 2.0

@export var world: GameWorld
@export var hud: Hud

var state := State.INTRO
var level: Level
var elapsed := 0.0
var result_stars := 0
var cleared := false

var _overlay: Control
var _state_before_pause := State.PLAY
var _was_captured := false
var _chain := 0
var _chain_timer := 0.0
var _last_destruction := 0.0
var _gain := 0.0
var _gain_timer := 0.0
var _end_timer := 0.0


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
	hud.set_title(level.title.to_upper())
	hud.target = level.target
	hud.sandbox = level.is_sandbox()
	if hud.touch:
		hud.add_pause_button(pause)
	world.structures.destruction_changed.connect(_on_destruction)
	world.structures.cluster_released.connect(_on_released)
	world.structures.cluster_impact.connect(_on_impact)
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
	var idx := GameState.index_of(world.level_file)
	var kicker := "BAC À SABLE" if level.is_sandbox() else "NIVEAU %d" % (idx + 1)
	box.add_child(UiTheme.label(kicker, "SmallLabel"))
	box.add_child(UiTheme.label(level.title, "TitleLabel"))
	if level.hint != "":
		var hint := UiTheme.label(level.hint)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 520
		box.add_child(hint)
	if not level.is_sandbox():
		box.add_child(_spacer(4))
		var t := level.star_times
		var best := GameState.best_time(world.level_file)
		var goal := (
			"Détruis %d%% et survis   ·   ★★★ %s   ★★ %s"
			% [roundi(level.target * 100), _clock(t.x), _clock(t.y)]
		)
		box.add_child(UiTheme.label(goal, "HeadLabel"))
		if best > 0.0:
			box.add_child(UiTheme.label("record %s" % _clock(best), "SmallLabel"))
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
			+ "maintiens le bouton violet pour grossir, relâche pour lancer · choisis le pouvoir au-dessus"
		)
	return (
		"1 Singularité · 2 Portail · 3 Bouclier  (molette, A/E)\n"
		+ "maintiens le clic pour grossir, relâche pour lancer · ZQSD bouger · R recommencer"
	)


func _begin_play() -> void:
	_clear_overlay()
	state = State.PLAY
	elapsed = 0.0
	world.player.input_enabled = true
	if not hud.touch and not Launch.options.has("mode"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func pause() -> void:
	if state not in [State.PLAY, State.CLEARED]:
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
	box.add_child(UiTheme.button("Recommencer", _restart))
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


func _on_died() -> void:
	if level.is_sandbox():
		hud.popup("AÏE", UiTheme.INK, 48)
		await get_tree().create_timer(SANDBOX_RESPAWN, true, false, true).timeout
		world.player.respawn()
		world.player.input_enabled = state == State.PLAY
		return
	if state != State.PLAY:
		return
	state = State.DEAD
	cleared = false
	_end_timer = 0.0
	Sfx.ui("death", -2.0)
	hud.popup("K.O.", Color(0.85, 0.1, 0.2), 64)


func _on_cleared() -> void:
	state = State.CLEARED
	cleared = true
	result_stars = level.stars_for(elapsed)
	_end_timer = 0.0
	hud.popup("OBJECTIF !", UiTheme.VIOLET, 60, Vector2(0, -40))
	Sfx.ui("fanfare", -6.0)


func _show_result() -> void:
	state = State.RESULT
	world.player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var path := world.level_file
	var best_before := GameState.best_time(path)
	var new_best := false
	if cleared:
		new_best = GameState.record(path, result_stars, elapsed)
	finished.emit(cleared, result_stars if cleared else 0, elapsed)
	var box := _panel()
	var d := world.structures.destruction()
	if cleared:
		box.add_child(UiTheme.label("Rasé en %s" % _clock(elapsed), "TitleLabel"))
	else:
		box.add_child(UiTheme.label("K.O.", "TitleLabel"))
		box.add_child(
			UiTheme.label(
				"Tu t'es fait écraser à %d%% / %d%%" % [roundi(d * 100), roundi(level.target * 100)]
			)
		)
	var stars := StarRow.new()
	stars.custom_minimum_size = Vector2(300, 84)
	box.add_child(stars)
	if cleared:
		var t := level.star_times
		box.add_child(UiTheme.label("★★★ %s   ·   ★★ %s" % [_clock(t.x), _clock(t.y)], "SmallLabel"))
		var best_text := (
			"nouveau record !"
			if new_best and best_before > 0.0
			else "record %s" % _clock(minf(elapsed, best_before) if best_before > 0.0 else elapsed)
		)
		box.add_child(
			UiTheme.label(best_text, "HeadLabel" if new_best and best_before > 0.0 else "SmallLabel")
		)
	box.add_child(_spacer(8))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var retry := UiTheme.button("Rejouer", _restart, 160)
	row.add_child(retry)
	var first: Button = retry
	var next := GameState.next_level(path)
	if cleared and next != "" and GameState.is_unlocked(next):
		var nb := UiTheme.button("Suivant", GameState.start_level.bind(next), 160)
		row.add_child(nb)
		first = nb
	row.add_child(UiTheme.button("Niveaux", GameState.go_to_menu, 160))
	first.grab_focus()
	if not cleared:
		return
	for k in result_stars:
		await get_tree().create_timer(0.35 + k * 0.3, true, false, true).timeout
		stars.lit = k + 1
		Sfx.ui("star", -4.0, 1.0 + k * 0.25)


# --- Events ---------------------------------------------------------------------


func _on_destruction(fraction: float) -> void:
	hud.destruction = fraction
	_gain += fraction - _last_destruction
	_last_destruction = fraction
	_gain_timer = 0.6
	if state == State.PLAY and not level.is_sandbox() and fraction >= level.target - 0.0001:
		_on_cleared()


func _on_released(_at: Vector3, count: int, toppled: bool) -> void:
	if count >= 12:
		hud.popup("BASCULE !" if toppled else "EFFONDREMENT !", UiTheme.INK, 44)
		_bump_chain()


func _on_impact(_at: Vector3, _mass: float, _speed: float, count: int) -> void:
	if count >= 8:
		_bump_chain()


func _bump_chain() -> void:
	_chain = _chain + 1 if _chain_timer > 0.0 else 1
	_chain_timer = CHAIN_WINDOW
	if _chain >= 2:
		hud.popup("CHAÎNE ×%d" % _chain, UiTheme.VIOLET, 36 + _chain * 3, Vector2(0, 60))
		Sfx.ui("chain", -8.0, 0.9 + _chain * 0.1)


# --- Frame -----------------------------------------------------------------------


func _process(delta: float) -> void:
	if level == null:
		return
	# The clock runs on real time: slow motion is not a free pause.
	var real := delta / maxf(Engine.time_scale, 0.001)
	_chain_timer = maxf(_chain_timer - real, 0.0)
	if _gain_timer > 0.0:
		_gain_timer -= real
		if _gain_timer <= 0.0 and _gain >= 0.02:
			hud.popup("+%d%%" % roundi(_gain * 100.0), UiTheme.VIOLET, 30, Vector2(260, -110))
		if _gain_timer <= 0.0:
			_gain = 0.0
	if Input.is_action_just_pressed("reset_arena") and state != State.PAUSED:
		_restart()
		return
	match state:
		State.PLAY, State.CLEARED, State.DEAD:
			if state == State.PLAY and not level.is_sandbox():
				elapsed += real
			hud.clock = elapsed
			if state != State.PLAY:
				_end_timer += real
				if _end_timer > RESULT_DELAY:
					_show_result()
					return
			# Browsers drop pointer lock on Esc without sending the key.
			var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			if (
				state != State.DEAD
				and ((_was_captured and not captured) or Input.is_action_just_pressed("release_mouse"))
			):
				pause()
				return
			_was_captured = captured
		State.PAUSED:
			if Input.is_action_just_pressed("release_mouse"):
				_resume()


static func _clock(seconds: float) -> String:
	var m := int(seconds / 60.0)
	var s := seconds - m * 60.0
	return "%d:%04.1f" % [m, s]


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


## Three big stars; `lit` of them filled.
class StarRow:
	extends Control
	var lit := 0:
		set(v):
			lit = v
			_pop = 1.0
			queue_redraw()
	var _pop := 0.0

	func _process(delta: float) -> void:
		if _pop > 0.0:
			_pop = maxf(_pop - delta * 4.0, 0.0)
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		for k in 3:
			var p := c + Vector2((k - 1) * 84.0, 6.0 if k == 1 else 14.0)
			var r := 32.0 if k == 1 else 26.0
			if k == lit - 1:
				r *= 1.0 + _pop * 0.35
			UiTheme.draw_star(self, p, r, UiTheme.STAR_ON if k < lit else UiTheme.STAR_OFF)
