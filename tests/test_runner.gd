extends Node
## Runs every tests/test_*.gd headlessly and exits with the failure count.
## godot --headless --path . res://tests/test_runner.tscn


func _ready() -> void:
	var failed := 0
	var passed := 0
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for f in files:
		if (
			not (f.begins_with("test_") and f.ends_with(".gd"))
			or f == "test_runner.gd"
			or f == "test_case.gd"
		):
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL ", f, " (script failed to load)")
			continue
		var suite: TestCase = script.new()
		add_child(suite)
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			suite.current = "%s::%s" % [f.get_basename(), name]
			var before := suite.failures.size()
			await suite.call(name)
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
