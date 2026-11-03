class_name MainMenu
extends Control
## Title screen over the live attract-mode arena: play, level select,
## sandbox. Works with mouse, keyboard, gamepad (focus) and touch.

var _page: Control


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_home()


func _show_home() -> void:
	remove_from_group("menu_busy")
	var box := _page_box()
	var title := UiTheme.label("GRAVITY", "TitleLabel")
	title.add_theme_font_size_override("font_size", 84)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(title)
	var sub := UiTheme.label("charge · throw · collapse", "SmallLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(sub)
	box.add_child(_gap(18))
	var cont := GameState.continue_level()
	var label := (
		"Play" if GameState.total_stars() == 0 else "Continue · level %d" % (GameState.index_of(cont) + 1)
	)
	var play := UiTheme.button(label, GameState.start_level.bind(cont), 300)
	box.add_child(play)
	box.add_child(UiTheme.button("Levels", _show_levels, 300))
	box.add_child(UiTheme.button("Sandbox", GameState.start_level.bind(GameState.SANDBOX), 300))
	if not OS.has_feature("web"):
		box.add_child(UiTheme.button("Quit", get_tree().quit, 300))
	box.add_child(_gap(10))
	var stars := UiTheme.label(
		"★ %d / %d" % [GameState.total_stars(), GameState.LEVELS.size() * 3], "SmallLabel"
	)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(stars)
	play.grab_focus()
	_report_play_button.call_deferred(play)


## Lets the CI touch probe find the Play button.
func _report_play_button(play: Button) -> void:
	await get_tree().process_frame
	var c := play.get_global_rect().get_center()
	print("MENU_PLAY %d %d" % [c.x, c.y])


func _show_levels() -> void:
	add_to_group("menu_busy")
	var box := _page_box()
	var head := UiTheme.label("Levels", "TitleLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var first: Button
	for i in GameState.LEVELS.size():
		var path := GameState.LEVELS[i]
		var b := LevelButton.new()
		b.number = i + 1
		b.stars = GameState.stars(path)
		b.disabled = not GameState.is_unlocked(path)
		b.custom_minimum_size = Vector2(92, 92)
		b.pressed.connect(GameState.start_level.bind(path))
		b.pressed.connect(func() -> void: Sfx.ui("click"))
		grid.add_child(b)
		if first == null and not b.disabled and b.stars == 0:
			first = b
	box.add_child(_gap(8))
	var back := UiTheme.button("Back", _show_home, 300)
	box.add_child(back)
	(first if first else back).grab_focus()


func _page_box() -> VBoxContainer:
	if _page:
		_page.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	_page = margin
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Square level button: number and up to three stars, greyed when locked.
class LevelButton:
	extends Button
	var number := 1
	var stars := 0

	func _draw() -> void:
		var font := UiTheme.bold()
		var ink := UiTheme.INK if not disabled else Color(UiTheme.INK, 0.25)
		if has_focus() or button_pressed:
			ink = UiTheme.INK
		var txt := str(number) if not disabled else "–"
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 34)
		draw_string(
			font, Vector2((size.x - ts.x) * 0.5, size.y * 0.55), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink
		)
		for k in 3:
			var on := k < stars
			UiTheme.draw_star(
				self,
				Vector2(size.x * 0.5 + (k - 1) * 20.0, size.y * 0.78),
				8.0,
				UiTheme.STAR_ON if on else UiTheme.STAR_OFF
			)
