@tool
class_name Level
extends Node3D
## Root of a level scene: a title, a hint for the intro card, Structure nodes
## and a PlayerStart. Open the .tscn in the editor to move structures around
## (they preview).

@export var title := "Level"
## Shown on the intro card.
@export_multiline var hint := ""


func player_start() -> Transform3D:
	var m := get_node_or_null("PlayerStart") as Node3D
	return m.global_transform if m else Transform3D(Basis(), Vector3(0, 0.05, 15))


func structures() -> Array[Structure]:
	var out: Array[Structure] = []
	for n in find_children("*", "Node3D", true, false):
		if n is Structure:
			out.append(n)
	return out
