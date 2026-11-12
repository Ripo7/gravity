extends Node
## Reads launch options. Desktop: `godot -- --mode=showcase --quality=low`.
## Web: `index.html?quality=low`.
##   --quality=low|medium|high  forces a quality tier (phone settings on a
##                              desktop, for measurements)
##   --mode=...                 a scripted run, see Director

var options := {}


func _enter_tree() -> void:
	options = parse(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("window.location.search", true)
		if query is String:
			options.merge(parse_query(query), true)
	if options.has("quality"):
		Quality.force(["low", "medium", "high"].find(options["quality"]))


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
