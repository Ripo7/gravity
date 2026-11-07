extends TestCase
## The starting scene: crates fall and land on the floor, a tap drops one.

var main: Main


func test_crates_land_on_the_floor() -> void:
	await _load()
	check_eq(main.crates.size(), 6, "six crates to start with")
	await frames(180)
	for c in main.crates:
		check(
			c.global_position.y > 0.2 and c.global_position.y < 6.0, "a crate rests on the floor or the pile"
		)
	await _unload()


func test_a_tap_drops_a_crate_where_you_point() -> void:
	await _load()
	var middle := get_viewport().get_visible_rect().size * 0.5
	main.drop_at_screen(middle)
	check_eq(main.crates.size(), 7, "one more crate")
	await frames(120)
	var landed := main.crates[-1].global_position
	check(landed.y < 2.0, "it fell down (%s)" % landed)
	await _unload()


func _load() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	# The runner may still be setting up the tree: add it on the next frame.
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(2)


func _unload() -> void:
	main.queue_free()
	await frames(2)
