class_name AdaptiveQuality
extends Node
## Keeps the game smooth without giving up the look where it can afford it.
## At start it applies the platform tier (shadow range, render scale, glow).
## Then it watches the frame time: when frames run long it first lowers the
## 3D render scale a notch (the interface stays sharp), then keeps fewer
## loose pieces around and lets every shard collide as a cheap box; when
## there is headroom again it steps back up.

const SLOW_MS := 24.0  ## average frame time that counts as struggling
## A window counts as calm when frames run this close to the best the screen
## allows (vsync caps a 60 Hz screen at 16.7 ms, whatever the headroom).
const CALM_RATIO := 1.12
const CALM_MS := 13.0  ## always calm below this (fast screens, no vsync)
const OUTLIER_MS := 250.0  ## longer frames (tab switch, loading) are ignored
const WINDOW := 2.0  ## seconds per measurement
const SCALE_STEP := 0.1

var world: GameWorld
var level := 0  ## 0 = full quality for this tier, up to 4 = lightest
var _base_scale := 1.0
var _floor_scale := 0.6
var _sum := 0.0
var _frames := 0
var _t := 0.0
var _calm_windows := 0
var _best_ms := INF  ## fastest window seen: roughly the screen's refresh
var _failures := PackedInt32Array([0, 0, 0, 0, 0])  ## times each level proved too heavy


func _ready() -> void:
	var vp := get_viewport()
	# Phones render 3D well under their 3x screens; the interface stays sharp.
	_base_scale = float(Quality.pick(0.6, 0.95, 1.0))
	_floor_scale = float(Quality.pick(0.45, 0.6, 0.6))
	vp.scaling_3d_scale = _base_scale
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.directional_shadow_max_distance = float(Quality.pick(40.0, 60.0, 80.0))
		sun.shadow_blur = float(Quality.pick(1.0, 1.4, 1.6))
		if Quality.tier() == Quality.Tier.LOW:
			# Two cascades instead of four: the city is drawn twice less.
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(int(Quality.pick(1024, 2048, 4096)), true)
	# Carved joints: one read on phones, a few steps in browsers, more here.
	for mat: Variant in [world.structures.material, world.debris.material]:
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("parallax_steps", int(Quality.pick(0, 6, 12)))
	var env := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env and env.environment and Quality.tier() == Quality.Tier.LOW:
		env.environment = env.environment.duplicate()
		env.environment.glow_enabled = false
	# Phones: no full-screen vignette pass (fill rate).
	var vignette := world.get_node_or_null("UI/Vignette") as CanvasItem
	if vignette and Quality.tier() == Quality.Tier.LOW:
		vignette.visible = false


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless" or Engine.time_scale < 0.99:
		return
	_t += delta
	if delta * 1000.0 < OUTLIER_MS:
		_sum += delta
		_frames += 1
	if _t < WINDOW:
		return
	var avg := _sum / maxf(_frames, 1) * 1000.0
	_sum = 0.0
	_frames = 0
	_t = 0.0
	if avg <= 0.0:
		return
	_best_ms = minf(_best_ms, avg)
	var calm := avg < maxf(CALM_MS, _best_ms * CALM_RATIO)
	if avg > SLOW_MS and level < 4:
		_calm_windows = 0
		_failures[level] += 1
		_set_level(level + 1)
	elif calm and level > 0:
		_calm_windows += 1
		# A level that proved too heavy before waits longer to come back.
		if _calm_windows >= 3 * (1 + mini(_failures[level - 1], 3)):
			_calm_windows = 0
			_set_level(level - 1)
	else:
		_calm_windows = 0


func _set_level(l: int) -> void:
	level = l
	# Render scale first (cheapest to notice), then fewer pieces kept and
	# box collisions only.
	get_viewport().scaling_3d_scale = maxf(_base_scale - SCALE_STEP * mini(l, 2), _floor_scale)
	if world and world.debris:
		world.debris.soft_budget = 0.8 - 0.15 * maxi(l - 2, 0)
		world.debris.hull_min_volume = INF if l >= 3 else DebrisSystem.tier_hull_min_volume()
