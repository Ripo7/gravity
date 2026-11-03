extends Node
## Reads launch options and, if a scripted mode is requested, attaches a
## Director to the main scene. Desktop: `godot -- --mode=bench`.
## Web: `index.html?mode=bench`.

var options := {}


func _ready() -> void:
	options = parse(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("window.location.search", true)
		if query is String:
			options.merge(parse_query(query), true)
	if options.get("mode", "") == "bench":
		DebrisSystem.capacity_override = int(options.get("max", "3000"))
	if options.has("mode"):
		get_tree().process_frame.connect(_attach, CONNECT_ONE_SHOT)


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
