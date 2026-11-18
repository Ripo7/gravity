class_name Glitter
extends Node3D
## Glass that has burst (docs/CONCEPT.md): small flat bits that fall
## straight down, lie where they land a moment and are gone. They are not
## bodies: nothing runs into them, nothing piles up on them. Each pane that
## bursts is one multimesh, moved by its shader (shaders/glitter.gdshader)
## from how long ago it burst; it is freed once its last bit is gone.

const SHADER := preload("res://shaders/glitter.gdshader")
## Bits for each square metre of pane, and the most for one pane.
const DENSE := 45.0
const MOST := 200
## A bit lies LIES s where it landed, then takes FADES s to be gone.
const LIES := 1.2
const FADES := 0.6

## Panes whose bits are still there.
var bursts := 0

var _quad := QuadMesh.new()
var _ages: Array[float] = []
var _lasts: Array[float] = []


## A pane `size` across, placed at `xf`, bursts: its bits start where it
## stood, `tint` in colour, and fall as fast as things do on the bench
## (`fall`: the share of real gravity).
func burst(xf: Transform3D, size: Vector3, tint: Color, fall: float) -> void:
	var gravity := Rubble.GRAVITY * fall
	var faces: Array[float] = [size.x * size.y, size.y * size.z, size.x * size.z]
	var count := clampi(roundi((faces.max() as float) * DENSE), 8, MOST)
	var bits := MultiMesh.new()
	bits.transform_format = MultiMesh.TRANSFORM_3D
	bits.use_custom_data = true
	bits.mesh = _quad
	bits.instance_count = count
	for k in count:
		var at := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * size
		bits.set_instance_transform(k, Transform3D(Basis(), xf * at))
		bits.set_instance_custom_data(k, Color(randf(), randf(), randf(), randf()))
	var paint := ShaderMaterial.new()
	paint.shader = SHADER
	var ground := xf.origin.y - size.y * 0.5
	paint.set_shader_parameter("gravity", gravity)
	paint.set_shader_parameter("ground", ground)
	paint.set_shader_parameter("lies", LIES)
	paint.set_shader_parameter("fades", FADES)
	paint.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	var shown := MultiMeshInstance3D.new()
	shown.multimesh = bits
	shown.material_override = paint
	shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (Its bits are drawn far from where the node is: never culled.)
	shown.custom_aabb = AABB(Vector3.ONE * -1000.0, Vector3.ONE * 2000.0)
	add_child(shown)
	_ages.append(0.0)
	# The highest bit lands last.
	_lasts.append(sqrt(2.0 * size.y / gravity) + LIES + FADES + 0.1)
	bursts += 1


func _process(delta: float) -> void:
	for k in range(get_child_count() - 1, -1, -1):
		_ages[k] += delta
		var shown := get_child(k) as MultiMeshInstance3D
		if _ages[k] >= _lasts[k]:
			_ages.remove_at(k)
			_lasts.remove_at(k)
			remove_child(shown)
			shown.queue_free()
			bursts -= 1
		else:
			(shown.material_override as ShaderMaterial).set_shader_parameter("age", _ages[k])
