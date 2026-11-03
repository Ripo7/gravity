class_name LevelRun
extends Node
## Flow of one level: intro card -> play -> settle -> results, plus pause.
## Also turns structural events into callouts (collapse, chain) for the HUD.

signal finished(stars: int, score: int)

enum State { INTRO, PLAY, SETTLE, RESULT, PAUSED }

const CHARGE_BONUS := 150
const SETTLE_MIN := 2.5  ## seconds after the last burst before judging
const SETTLE_MAX := 12.0
const CHAIN_WINDOW := 1.4

@export var world: GameWorld
@export var hud: Hud

var state := State.INTRO
var charges_left := 0
var level: Level
var result_stars := 0
var result_score := 0

var _overlay: Control
var _settle_time := 0.0
var _quiet_time := 0.0
var _state_before_pause := State.PLAY
var _was_captured := false
var _chain := 0
var _chain_timer := 0.0
var _last_destruction := 0.0
var _gain := 0.0
var _gain_timer := 0.0
var _card_stars_shown := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not world.is_node_ready():
		await world.ready
	level = world.level
	if level == null or world.attract:
		hud.visible = false
		level = null
		return
	charges_left = level.charges
	_overlay = Control.new()
	_overlay.theme = UiTheme.get_theme()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.get_parent().add_child(_overlay)
	hud.set_title(level.title.to_upper())
	hud.thresholds = level.star_thresholds
	hud.charges_total = level.charges
	hud.charges_left = charges_left
	if hud.touch:
		hud.add_pause_button(pause)
	world.player.power.thrown.connect(_on_thrown)
	world.structures.destruction_changed.connect(_on_destruction)
	world.structures.cluster_released.connect(_on_released)
	world.structures.cluster_impact.connect(_on_impact)
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
	var idx := GameState.index_of(GameState.current_level)
	var kicker := "SANDBOX" if level.is_sandbox() else "LEVEL %d" % (idx + 1)
	box.add_child(UiTheme.label(kicker, "SmallLabel"))
	box.add_child(UiTheme.label(level.title, "TitleLabel"))
	if level.hint != "":
		var hint := UiTheme.label(level.hint)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 460
		box.add_child(hint)
	if not level.is_sandbox():
		box.add_child(_spacer(6))
		var t := level.star_thresholds
		box.add_child(
			UiTheme.label(
				(
					"%d charges   ·   ★ %d%%   ★★ %d%%   ★★★ %d%%"
					% [level.charges, roundi(t.x * 100), roundi(t.y * 100), roundi(t.z * 100)]
				),
				"SmallLabel"
			)
		)
	box.add_child(_spacer(8))
	var controls := (
		"left thumb: move · drag right: look · hold violet button: charge"
		if hud.touch
		else "WASD move · mouse look · hold click to charge, release to throw · R restart"
	)
	box.add_child(UiTheme.label(controls, "SmallLabel"))
	box.add_child(_spacer(8))
	var start := UiTheme.button("Start", _begin_play)
	box.add_child(start)
	start.grab_focus()


func _begin_play() -> void:
	_clear_overlay()
	state = State.PLAY
	world.player.input_enabled = true
	world.player.power.enabled = level.is_sandbox() or charges_left > 0
	if not hud.touch and not Launch.options.has("mode"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func pause() -> void:
	if state not in [State.PLAY, State.SETTLE]:
		return
	_state_before_pause = state
	state = State.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := _panel()
	box.add_child(UiTheme.label("Paused", "TitleLabel"))
	box.add_child(_spacer(6))
	var resume := UiTheme.button("Resume", _resume)
	box.add_child(resume)
	box.add_child(UiTheme.button("Restart", _restart))
	box.add_child(UiTheme.button("Main menu", GameState.go_to_menu))
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


func _finish() -> void:
	state = State.RESULT
	world.player.input_enabled = false
	world.player.power.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var d := world.structures.destruction()
	result_stars = level.stars_for(d)
	result_score = int(round(d * 1000.0)) + (charges_left * CHARGE_BONUS if result_stars > 0 else 0)
	var best_before := GameState.best_score(GameState.current_level)
	var new_best := GameState.record(GameState.current_level, result_stars, result_score, d)
	finished.emit(result_stars, result_score)
	var box := _panel()
	var head := "Demolished!" if result_stars == 3 else ("Level clear" if result_stars > 0 else "Not enough")
	box.add_child(UiTheme.label(head, "TitleLabel"))
	var stars := StarRow.new()
	stars.custom_minimum_size = Vector2(300, 84)
	box.add_child(stars)
	box.add_child(UiTheme.label("%d%% destroyed" % int(round(d * 100.0)), "HeadLabel"))
	var detail := "score %d" % result_score
	if charges_left > 0 and result_stars > 0:
		detail += "   (+%d unused charges)" % (charges_left * CHARGE_BONUS)
	box.add_child(UiTheme.label(detail))
	var best_text := (
		"new best!" if new_best and best_before > 0 else "best %d" % maxi(best_before, result_score)
	)
	box.add_child(UiTheme.label(best_text, "SmallLabel"))
	box.add_child(_spacer(8))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var retry := UiTheme.button("Retry", _restart, 150)
	row.add_child(retry)
	var next := GameState.next_level(GameState.current_level)
	var first: Button = retry
	if next != "" and GameState.is_unlocked(next):
		var nb := UiTheme.button("Next", GameState.start_level.bind(next), 150)
		row.add_child(nb)
		first = nb
	row.add_child(UiTheme.button("Levels", GameState.go_to_menu, 150))
	first.grab_focus()
	# Stars pop in one by one.
	for k in result_stars:
		await get_tree().create_timer(0.35 + k * 0.3, true, false, true).timeout
		stars.lit = k + 1
		Sfx.ui("star", -4.0, 1.0 + k * 0.25)
	if result_stars > 0:
		await get_tree().create_timer(0.3, true, false, true).timeout
		Sfx.ui("fanfare", -6.0)


# --- Events ---------------------------------------------------------------------


func _on_thrown(_params: BlastParams) -> void:
	if level.is_sandbox():
		return
	charges_left = maxi(charges_left - 1, 0)
	hud.charges_left = charges_left
	if charges_left == 0:
		world.player.power.enabled = false
		state = State.SETTLE
		_settle_time = 0.0
		_quiet_time = 0.0


func _on_destruction(fraction: float) -> void:
	hud.destruction = fraction
	_gain += fraction - _last_destruction
	_last_destruction = fraction
	_gain_timer = 0.6
	# Reaching a star threshold is worth a callout.
	var stars := level.stars_for(fraction)
	if not level.is_sandbox() and stars > _card_stars_shown:
		_card_stars_shown = stars
		hud.popup("★".repeat(stars), UiTheme.STAR_ON, 54, Vector2(0, -90))
		Sfx.ui("star", -6.0, 1.0 + stars * 0.2)
		hud.pulse_meter()


func _on_released(_at: Vector3, count: int, toppled: bool) -> void:
	if count >= 12:
		hud.popup("TOPPLED!" if toppled else "COLLAPSE!", UiTheme.INK, 44)
		_bump_chain()


func _on_impact(_at: Vector3, _mass: float, _speed: float, count: int) -> void:
	if count >= 8:
		_bump_chain()


func _bump_chain() -> void:
	_chain = _chain + 1 if _chain_timer > 0.0 else 1
	_chain_timer = CHAIN_WINDOW
	if _chain >= 2:
		hud.popup("CHAIN ×%d" % _chain, UiTheme.VIOLET, 36 + _chain * 3, Vector2(0, 60))
		Sfx.ui("chain", -8.0, 0.9 + _chain * 0.1)


# --- Frame -----------------------------------------------------------------------


func _process(delta: float) -> void:
	if level == null:
		return
	var real := delta / maxf(Engine.time_scale, 0.001)
	_chain_timer = maxf(_chain_timer - real, 0.0)
	if _gain_timer > 0.0:
		_gain_timer -= real
		if _gain_timer <= 0.0 and _gain >= 0.02:
			hud.popup("+%d%%" % int(round(_gain * 100.0)), UiTheme.VIOLET, 30, Vector2(260, -110))
			_gain = 0.0
		elif _gain_timer <= 0.0:
			_gain = 0.0
	if Input.is_action_just_pressed("reset_arena") and state != State.PAUSED:
		_restart()
		return
	match state:
		State.PLAY, State.SETTLE:
			# Browsers drop pointer lock on Esc without sending the key.
			var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			if (_was_captured and not captured) or Input.is_action_just_pressed("release_mouse"):
				pause()
				return
			_was_captured = captured
			if state == State.SETTLE or _all_stars_reached():
				_check_settled(real)
		State.PAUSED:
			if Input.is_action_just_pressed("release_mouse"):
				_resume()


func _all_stars_reached() -> bool:
	return not level.is_sandbox() and world.structures.destruction() >= level.star_thresholds.z


## Ends the level once the dust has settled (or after SETTLE_MAX seconds).
func _check_settled(real: float) -> void:
	_settle_time += real
	var busy := world.structures.cluster_count() > 0
	for c in world.get_children():
		if c is GravityBlast:
			busy = true
	var moving := world.debris.awake_count > maxi(20, int(world.debris.active_count * 0.08))
	if busy or moving:
		_quiet_time = 0.0
	else:
		_quiet_time += real
	if (_settle_time > SETTLE_MIN and _quiet_time > 0.8) or _settle_time > SETTLE_MAX:
		_finish()


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
