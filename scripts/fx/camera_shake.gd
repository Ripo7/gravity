class_name CameraShake
extends Camera3D
## Trauma-based screen shake (shake = trauma^2) with smooth noise, plus a
## brief FOV punch. Runs on unscaled time so slow-motion stays readable.

@export var max_offset := 0.12
@export var max_roll := 0.05
@export var decay := 1.6
@export var base_fov := 80.0

var trauma := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	add_to_group("camera_shake")
	_noise.frequency = 0.9
	fov = base_fov


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(_delta: float) -> void:
	var dt := _real_delta()
	_time += dt * 40.0
	trauma = maxf(trauma - decay * dt, 0.0)
	var s := trauma * trauma
	h_offset = max_offset * s * _noise.get_noise_2d(_time, 0.0)
	v_offset = max_offset * s * _noise.get_noise_2d(0.0, _time)
	rotation.z = max_roll * s * _noise.get_noise_2d(_time, _time)
	fov = base_fov


func _real_delta() -> float:
	var scale := maxf(Engine.time_scale, 0.001)
	return get_process_delta_time() / scale
