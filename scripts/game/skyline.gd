@tool
class_name Skyline
extends Node3D
## The rest of the city around the playable district: rows of tall painted
## blocks with lit windows fading into the haze (no physics, one draw
## call), and invisible
## walls that keep the player inside.

const SKYLINE_SHADER := preload("res://shaders/skyline.gdshader")

## Half size of the playable square (the invisible walls stand on its edge).
@export var inner := 52.0:
	set(v):
		inner = v
		_rebuild()
## Half size of the outer edge of the skyline.
@export var outer := 78.0:
	set(v):
		outer = v
		_rebuild()
@export var seed_value := 3:
	set(v):
		seed_value = v
		_rebuild()

var _mesh: MultiMeshInstance3D
var _walls: StaticBody3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for n in [_mesh, _walls]:
		if n != null:
			n.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var boxes: Array[Transform3D] = []
	var shades: Array[float] = []
	var paints: Array[Color] = []
	# Two rings of blocks, the back one taller.
	for ring in 2:
		var d0 := inner + 2.0 + ring * 12.0
		var x := -outer
		while x < outer:
			var w := rng.randf_range(8.0, 14.0)
			for side in 4:
				var h := rng.randf_range(14.0, 30.0) + ring * 14.0
				var depth := rng.randf_range(8.0, 11.0)
				var c := Vector3(x + w * 0.5, h * 0.5, d0 + depth * 0.5)
				var b := Basis.from_euler(Vector3(0, side * PI * 0.5, 0))
				boxes.append(Transform3D(b.scaled(Vector3(w - 1.0, h, depth)), b * c))
				shades.append(rng.randf_range(0.82, 0.97))
				paints.append(Materials.PAINTS[rng.randi_range(0, Materials.PAINT_COUNT)])
			x += w
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	var m := ShaderMaterial.new()
	m.shader = SKYLINE_SHADER
	box.material = m
	mm.mesh = box
	mm.instance_count = boxes.size()
	for i in boxes.size():
		mm.set_instance_transform(i, boxes[i])
		# Painted like the district, a little paler with distance.
		var c := paints[i].lerp(Color(0.95, 0.9, 0.86), 0.3) * shades[i]
		c.a = rng.randf()
		mm.set_instance_color(i, c)
	_mesh = MultiMeshInstance3D.new()
	_mesh.multimesh = mm
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
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
