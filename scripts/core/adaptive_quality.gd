class_name AdaptiveQuality
extends Node
## Keeps the game smooth without giving up the look where it can afford it.
## At start it applies the platform tier (shadow range, render scale, glow).
## Then it watches the frame time: when frames run long it first lowers the
## 3D render scale a notch (the interface stays sharp), then keeps fewer
## loose pieces around and lets every shard collide as a cheap box; when
## there is headroom again it steps back up.

const SLOW_MS := 24.0  ## average frame time that counts as struggling
const FAST_MS := 13.0  ## comfortably fast: room to raise quality again
const WINDOW := 2.0  ## seconds per measurement
const SCALE_STEP := 0.1

var world: GameWorld
var level := 0  ## 0 = full quality for this tier, up to 4 = lightest
var _base_scale := 1.0
var _sum := 0.0
var _frames := 0
var _t := 0.0
var _fast_windows := 0


func _ready() -> void:
	var vp := get_viewport()
	_base_scale = float(Quality.pick(0.8, 0.95, 1.0))
	vp.scaling_3d_scale = _base_scale
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.directional_shadow_max_distance = float(Quality.pick(40.0, 60.0, 80.0))
		sun.shadow_blur = float(Quality.pick(1.0, 1.4, 1.6))
	RenderingServer.directional_shadow_atlas_set_size(int(Quality.pick(1024, 2048, 4096)), true)
	var env := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env and env.environment and Quality.tier() == Quality.Tier.LOW:
		env.environment = env.environment.duplicate()
		env.environment.glow_enabled = false


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless" or Engine.time_scale < 0.99:
		return
	_sum += delta
	_frames += 1
	_t += delta
	if _t < WINDOW:
		return
	var avg := _sum / maxf(_frames, 1) * 1000.0
	_sum = 0.0
	_frames = 0
	_t = 0.0
	if avg > SLOW_MS and level < 4:
		_fast_windows = 0
		_set_level(level + 1)
	elif avg < FAST_MS and level > 0:
		_fast_windows += 1
		if _fast_windows >= 3:  # only after 6 calm seconds
			_fast_windows = 0
			_set_level(level - 1)
	else:
		_fast_windows = 0


func _set_level(l: int) -> void:
	level = l
	# Render scale first (cheapest to notice), then fewer pieces kept and
	# box collisions only.
	get_viewport().scaling_3d_scale = maxf(_base_scale - SCALE_STEP * mini(l, 2), 0.6)
	if world and world.debris:
		world.debris.soft_budget = 0.8 - 0.15 * maxi(l - 2, 0)
		world.debris.hull_min_volume = INF if l >= 3 else DebrisSystem.tier_hull_min_volume()
