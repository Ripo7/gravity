class_name MainMenu
extends Control
## Title screen over the live attract-mode arena. Works with mouse,
## keyboard, gamepad (focus) and touch.

var _page: Control


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_home()


func _show_home() -> void:
	var box := _page_box()
	var title := UiTheme.label("GRAVITY", "TitleLabel")
	title.add_theme_font_size_override("font_size", 84)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(title)
	var sub := UiTheme.label("invoque · écrase · survis", "SmallLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(sub)
	box.add_child(_gap(18))
	var play := UiTheme.button("Jouer", GameState.start_level.bind(GameState.SANDBOX), 300)
	box.add_child(play)
	if not OS.has_feature("web"):
		box.add_child(UiTheme.button("Quitter", get_tree().quit, 300))
	play.grab_focus()
	_report_play_button.call_deferred(play)


## Lets the CI touch probe find the Play button.
func _report_play_button(play: Button) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(play) or not play.is_inside_tree():
		return
	var c := play.get_global_rect().get_center()
	print("MENU_PLAY %d %d" % [c.x, c.y])


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
