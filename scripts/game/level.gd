@tool
class_name Level
extends Node3D
## Root of a level scene: its rules, plus Structure nodes and a PlayerStart.
## Open a level .tscn in the editor to move structures around (they preview).

@export var title := "Level"
## One line shown on the level card: the goal or a hint.
@export_multiline var hint := ""
## Power balls available; 0 means unlimited (sandbox).
@export var charges := 2
## Share of the level destroyed for 1, 2 and 3 stars.
@export var star_thresholds := Vector3(0.4, 0.65, 0.85)


func is_sandbox() -> bool:
	return charges <= 0


func stars_for(destruction: float) -> int:
	var n := 0
	for k in 3:
		if destruction >= star_thresholds[k] - 0.0001:
			n += 1
	return n


func player_start() -> Transform3D:
	var m := get_node_or_null("PlayerStart") as Node3D
	return m.global_transform if m else Transform3D(Basis(), Vector3(0, 0.05, 15))


func structures() -> Array[Structure]:
	var out: Array[Structure] = []
	for n in find_children("*", "Node3D", true, false):
		if n is Structure:
			out.append(n)
	return out
