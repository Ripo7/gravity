@tool
class_name Arena
extends Node3D
## Invisible walls round the square, so the player stays on the paving.
## Beyond them only the plain and the haze.

## Half size of the playable square (the walls stand on its edge).
@export var inner := 52.0

var _walls: StaticBody3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_walls = StaticBody3D.new()
	for side in 4:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(inner * 2.0 + 2.0, 60.0, 1.0)
		shape.shape = bs
		var b := Basis.from_euler(Vector3(0, side * PI * 0.5, 0))
		shape.transform = Transform3D(b, b * Vector3(0, 30.0, inner + 0.5))
		_walls.add_child(shape)
	add_child(_walls)
