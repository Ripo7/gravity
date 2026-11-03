extends Node
## Autoload: level list, current level, and saved progress (stars, bests).
## Progress lives in user://progress.cfg (IndexedDB on the web build).

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const SANDBOX := "res://levels/sandbox.tscn"
const LEVELS: Array[String] = [
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
]
const SAVE_PATH := "user://progress.cfg"

var current_level := SANDBOX
## Set to false by tests so they never touch the player's save.
var persist := true

var _cfg := ConfigFile.new()


func _ready() -> void:
	if persist:
		_cfg.load(SAVE_PATH)


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


func index_of(path: String) -> int:
	return LEVELS.find(path)


func next_level(path: String) -> String:
	var i := index_of(path)
	return LEVELS[i + 1] if i >= 0 and i + 1 < LEVELS.size() else ""


## Level 1 is always open; each further level needs a star on the previous.
func is_unlocked(path: String) -> bool:
	var i := index_of(path)
	if i <= 0:
		return true
	return stars(LEVELS[i - 1]) > 0


func stars(path: String) -> int:
	return _cfg.get_value(path, "stars", 0)


func best_score(path: String) -> int:
	return _cfg.get_value(path, "score", 0)


func best_destruction(path: String) -> float:
	return _cfg.get_value(path, "destruction", 0.0)


func total_stars() -> int:
	var n := 0
	for p in LEVELS:
		n += stars(p)
	return n


## First level that is unlocked but not yet completed, else the last one.
func continue_level() -> String:
	for p in LEVELS:
		if is_unlocked(p) and stars(p) == 0:
			return p
	return LEVELS[LEVELS.size() - 1]


## Stores a result. Returns true when it beat the previous best score.
func record(path: String, star_count: int, score: int, destruction: float) -> bool:
	var better := score > best_score(path)
	_cfg.set_value(path, "stars", maxi(star_count, stars(path)))
	_cfg.set_value(path, "score", maxi(score, best_score(path)))
	_cfg.set_value(path, "destruction", maxf(destruction, best_destruction(path)))
	if persist:
		_cfg.save(SAVE_PATH)
	return better


func reset_progress() -> void:
	_cfg = ConfigFile.new()
	if persist:
		_cfg.save(SAVE_PATH)
