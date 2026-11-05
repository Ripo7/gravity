class_name PhysicsClock
extends Node
## What a physics step really costs, scripts and engine together: wall time
## from the first physics callback of a frame to the first process callback
## of that frame, divided by the steps it ran. Averaged per second.
## (Performance.TIME_PHYSICS_PROCESS is the worst step of the previous
## second, refreshed once a second: fine for spotting spikes, wrong for
## averages.)

## Average ms per physics step over the last full second.
var avg_ms := 0.0
## Worst single step (ms) in the last full second.
var worst_ms := 0.0
## Steps counted in the last full second.
var steps := 0
## Since the start: every step's cost, for percentiles in benchmarks.
var history := PackedFloat32Array()
var keep_history := false

var _first := 0
var _pending := 0
var _sum := 0
var _worst := 0
var _count := 0
var _t := 0.0


func _ready() -> void:
	# First in, first out: before every other physics and process callback.
	process_physics_priority = -1000000
	process_priority = -1000000


func _physics_process(_delta: float) -> void:
	if _pending == 0:
		_first = Time.get_ticks_usec()
	_pending += 1


func _process(delta: float) -> void:
	if _pending > 0:
		var us := Time.get_ticks_usec() - _first
		var per := us / _pending
		_sum += us
		_count += _pending
		_worst = maxi(_worst, per)
		if keep_history:
			for k in _pending:
				history.append(per / 1000.0)
		_pending = 0
	_t += delta / maxf(Engine.time_scale, 0.001)
	if _t >= 1.0:
		avg_ms = _sum / 1000.0 / maxi(_count, 1)
		worst_ms = _worst / 1000.0
		steps = _count
		_sum = 0
		_worst = 0
		_count = 0
		_t = 0.0


## Mean of the steps recorded since `from` (an index into history).
func mean_since(from: int) -> float:
	var n := history.size() - from
	if n <= 0:
		return 0.0
	var total := 0.0
	for k in range(from, history.size()):
		total += history[k]
	return total / n
