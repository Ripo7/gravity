extends Node
## Autoload: every sound effect. Pooled players, per-sound rate limits so a
## collapse of 200 blocks sounds like a rumble and not a machine gun.
## Sounds are synthesised by tools/make_sounds.py.

const POOL_3D := 14
const POOL_UI := 4
const MIN_GAP := 0.05  ## seconds between two starts of the same sound
const MAX_ALIVE := 4  ## same sound playing at once

const SOUNDS := {
	"implode": preload("res://audio/implode.wav"),
	"burst": preload("res://audio/burst.wav"),
	"break_concrete": preload("res://audio/break_concrete.wav"),
	"break_wood": preload("res://audio/break_wood.wav"),
	"break_metal": preload("res://audio/break_metal.wav"),
	"collapse": preload("res://audio/collapse.wav"),
	"creak": preload("res://audio/creak.wav"),
	"click": preload("res://audio/click.wav"),
	"star": preload("res://audio/star.wav"),
	"fanfare": preload("res://audio/fanfare.wav"),
	"chain": preload("res://audio/chain.wav"),
	"orb": preload("res://audio/orb.wav"),
	"ice_rise": preload("res://audio/ice_rise.wav"),
	"ice_hit": preload("res://audio/ice_hit.wav"),
	"ice_break": preload("res://audio/ice_break.wav"),
	"hurt": preload("res://audio/hurt.wav"),
	"death": preload("res://audio/death.wav"),
	"denied": preload("res://audio/denied.wav"),
	"select": preload("res://audio/select.wav"),
	"tier": preload("res://audio/tier.wav"),
	"ready": preload("res://audio/ready.wav"),
}
const BREAKS := {
	Materials.Kind.CONCRETE: "break_concrete",
	Materials.Kind.WOOD: "break_wood",
	Materials.Kind.METAL: "break_metal",
	Materials.Kind.ICE: "ice_hit",
}

var _players: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _charge: AudioStreamPlayer
var _next := 0
var _next_ui := 0
var _last := {}  # name -> time of last start
var _alive := {}  # name -> [player, ...]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 140.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		add_child(p)
		_players.append(p)
	for i in POOL_UI:
		var u := AudioStreamPlayer.new()
		add_child(u)
		_ui.append(u)
	_charge = AudioStreamPlayer.new()
	var loop := (load("res://audio/charge_loop.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	_charge.stream = loop
	_charge.volume_db = -14.0
	add_child(_charge)


## Plays a sound at a world position (Vector3.INF = not positional).
func play(sound: String, at := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void:
	if not SOUNDS.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -1.0)) < MIN_GAP:
		return
	var alive: Array = _alive.get(sound, [])
	alive = alive.filter(func(p: Node) -> bool: return is_instance_valid(p) and p.playing)
	if alive.size() >= MAX_ALIVE:
		return
	_last[sound] = now
	if at == Vector3.INF:
		ui(sound, volume_db, pitch)
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_3D
	p.stream = SOUNDS[sound]
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()
	alive.append(p)
	_alive[sound] = alive


func ui(sound: String, volume_db := -6.0, pitch := 1.0) -> void:
	if not SOUNDS.has(sound):
		return
	var u := _ui[_next_ui]
	_next_ui = (_next_ui + 1) % POOL_UI
	u.stream = SOUNDS[sound]
	u.volume_db = volume_db
	u.pitch_scale = pitch
	u.play()


## Breaking block: material picks the sound, size the pitch and loudness.
func play_break(kind: int, at: Vector3, radius: float) -> void:
	var pitch := clampf(1.35 - radius * 0.5, 0.6, 1.4)
	play(BREAKS.get(kind, "break_concrete"), at, -10.0 + radius * 6.0, pitch)


func start_charge() -> void:
	_charge.pitch_scale = 0.8
	_charge.play()


func update_charge(c: float) -> void:
	_charge.pitch_scale = 0.8 + c * 0.9
	_charge.volume_db = -16.0 + c * 8.0


func stop_charge() -> void:
	_charge.stop()
