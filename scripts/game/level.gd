@tool
class_name Level
extends Node3D
## Root of a level scene: its rules, plus Structure nodes and a PlayerStart.
## Open a level .tscn in the editor to move structures around (they preview).
##
## Rules (time attack): destroy `target` of the level as fast as you can and
## stay alive. Finishing gives 1 star, under `star_times.y` 2 stars, under
## `star_times.x` 3 stars.

@export var title := "Level"
## One line shown on the level card: the goal or a hint.
@export_multiline var hint := ""
## Share of the level to destroy (0..1).
@export_range(0.1, 1.0, 0.01) var target := 0.75
## Seconds for 3 stars (x) and 2 stars (y).
@export var star_times := Vector2(40, 75)
## Free play: no goal, no clock, you come back after dying.
@export var sandbox := false


func is_sandbox() -> bool:
	return sandbox


func stars_for(seconds: float) -> int:
	if seconds <= star_times.x:
		return 3
	if seconds <= star_times.y:
		return 2
	return 1


func player_start() -> Transform3D:
	var m := get_node_or_null("PlayerStart") as Node3D
	return m.global_transform if m else Transform3D(Basis(), Vector3(0, 0.05, 15))


func structures() -> Array[Structure]:
	var out: Array[Structure] = []
	for n in find_children("*", "Node3D", true, false):
		if n is Structure:
			out.append(n)
	return out
