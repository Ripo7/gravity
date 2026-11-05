extends Node
## Reads launch options and, if a scripted mode is requested, opens the
## game scene and attaches a Director to it.
## Desktop: `godot -- --mode=bench [--level=res://levels/level_04.tscn]`.
## Web: `index.html?mode=bench`. `--level` alone jumps straight into a level.
## `--quality=low|medium|high` forces a quality tier (e.g. phone settings
## on a desktop, for measurements).

var options := {}


func _ready() -> void:
	options = parse(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("window.location.search", true)
		if query is String:
			options.merge(parse_query(query), true)
	if options.has("quality"):
		Quality.force(["low", "medium", "high"].find(options["quality"]))
	if options.get("mode", "") == "bench":
		DebrisSystem.capacity_override = int(options.get("max", "3000"))
	if options.has("level"):
		GameState.current_level = options["level"]
	if options.has("mode") or options.has("level"):
		_open_game.call_deferred()


func _open_game() -> void:
	var stay: bool = options.get("mode", "") == "shot" and not options.has("level")
	if not stay and not (get_tree().current_scene is GameWorld and not get_tree().current_scene.attract):
		get_tree().change_scene_to_file(GameState.GAME_SCENE)
	if not options.has("mode"):
		return
	# Wait for the game scene to be ready, then attach the director.
	while not (get_tree().current_scene is GameWorld and get_tree().current_scene.is_node_ready()):
		await get_tree().process_frame
	_attach()


func _attach() -> void:
	var scene := get_tree().current_scene
	var director := Node.new()
	director.set_script(load("res://scripts/core/director.gd"))
	director.set("options", options)
	scene.add_child(director)


static func parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


static func parse_query(query: String) -> Dictionary:
	var out := {}
	for pair in query.trim_prefix("?").split("&", false):
		var kv := pair.split("=", true, 1)
		out[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else "true"
	return out
