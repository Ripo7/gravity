extends Node
## Autoload: which level to load and scene changes. For now there is one
## level, the sandbox.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const SANDBOX := "res://levels/sandbox.tscn"

var current_level := SANDBOX


func start_level(path: String) -> void:
	current_level = path
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)
