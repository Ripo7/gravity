class_name BlastWave
extends MeshInstance3D
## A shock wave you can see: a shell of bent air with a bright rim that
## grows from `from_radius` to `to_radius` (a blast) or shrinks (an
## implosion) in `duration` seconds, fading as it goes, then frees itself.
## With a cone it is only the cap of the shell around -Z (a forward blast).

const SHADER := preload("res://shaders/shock_wave.gdshader")

var from_radius := 0.5
var to_radius := 8.0
var duration := 0.5
var _t := 0.0
var _mat: ShaderMaterial


## Adds a wave to `parent` at `xf` (-Z is the way a cone points). `cone`
## is the half angle in degrees, 0 for a whole sphere.
static func spawn(
	parent: Node, xf: Transform3D, from_r: float, to_r: float, time: float, tint: Color, cone := 0.0
) -> BlastWave:
	var w := BlastWave.new()
	w.from_radius = from_r
	w.to_radius = to_r
	w.duration = time
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 40
	s.rings = 20
	w.mesh = s
	w._mat = ShaderMaterial.new()
	w._mat.shader = SHADER
	w._mat.set_shader_parameter("tint", tint)
	w._mat.set_shader_parameter("cone_cos", cos(deg_to_rad(cone)) if cone > 0.0 else -2.0)
	w.material_override = w._mat
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(w)
	w.global_transform = xf
	w._apply()
	return w


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_apply()


func _apply() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	# Fast at first, slowing down: a blast; an implosion speeds up instead.
	var grow := to_radius > from_radius
	var e := 1.0 - pow(1.0 - k, 2.2) if grow else pow(k, 1.8)
	scale = Vector3.ONE * maxf(lerpf(from_radius, to_radius, e), 0.01)
	_mat.set_shader_parameter("fade", (1.0 - k) * minf(k * 12.0, 1.0) if grow else 1.0 - pow(k, 4.0))
