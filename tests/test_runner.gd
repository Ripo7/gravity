extends Node
## Runs every tests/test_*.gd headlessly and exits with the failure count.
## godot --headless --path . res://tests/test_runner.tscn [-- --only=main]
## A test fails on a failed check, and also on any script or engine error
## logged while it runs (a runtime error stops a test short of its checks).


class ErrorCounter:
	extends Logger
	var count := 0

	func _log_error(
		_function: String,
		_file: String,
		_line: int,
		_code: String,
		_rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			count += 1


func _ready() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var failed := 0
	var passed := 0
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for f in files:
		if (
			not (f.begins_with("test_") and f.ends_with(".gd"))
			or f == "test_runner.gd"
			or f == "test_case.gd"
			or (only != "" and not f.contains(only))
		):
			continue
		var script: GDScript = load("res://tests/" + f)
		var suite: TestCase = null
		if script != null and script.can_instantiate():
			suite = script.new() as TestCase
		if suite == null:
			failed += 1
			print("  FAIL ", f, " (script failed to load or does not extend TestCase)")
			continue
		add_child(suite)
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			suite.current = "%s::%s" % [f.get_basename(), name]
			if not (m["args"] as Array).is_empty():
				failed += 1
				print("  FAIL ", suite.current, " (test methods take no arguments)")
				continue
			var before := suite.failures.size()
			var errors_before := errors.count
			await suite.call(name)
			if errors.count > errors_before:
				suite.failures.append(
					"%s: %d error(s) logged while it ran" % [suite.current, errors.count - errors_before]
				)
			if suite.failures.size() == before:
				passed += 1
				print("  ok   ", suite.current)
			else:
				failed += 1
				print("  FAIL ", suite.current)
				for msg in suite.failures.slice(before):
					print("       ", msg)
		suite.queue_free()
		await get_tree().process_frame
	print("\n%d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
