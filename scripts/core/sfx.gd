extends Node
## Autoload: every sound effect. Pooled players, per-sound rate limits so a
## collapse of 200 blocks sounds like a rumble and not a machine gun.
## Sounds are synthesised by tools/make_sounds.py, the music and the
## ambience (two seamless loops that always play) by tools/make_music.py.

const POOL_3D := 14
const POOL_UI := 4
const MIN_GAP := 0.05  ## seconds between two starts of the same sound
const MAX_ALIVE := 4  ## same sound playing at once
const MUSIC_DB := -15.0
const AMBIENCE_DB := -11.0

const SOUNDS := {
	"implode": preload("res://audio/implode.wav"),
	"burst": preload("res://audio/burst.wav"),
	"break_concrete": preload("res://audio/break_concrete.wav"),
	"break_wood": preload("res://audio/break_wood.wav"),
	"break_metal": preload("res://audio/break_metal.wav"),
	"collapse": preload("res://audio/collapse.wav"),
	"creak": preload("res://audio/creak.wav"),
	"click": preload("res://audio/click.wav"),
	"orb": preload("res://audio/orb.wav"),
	"ice_rise": preload("res://audio/ice_rise.wav"),
	"ice_hit": preload("res://audio/ice_hit.wav"),
	"ice_break": preload("res://audio/ice_break.wav"),
	"hurt": preload("res://audio/hurt.wav"),
	"death": preload("res://audio/death.wav"),
	"denied": preload("res://audio/denied.wav"),
	"select": preload("res://audio/select.wav"),
	"ready": preload("res://audio/ready.wav"),
}
const BREAKS := {
	Materials.Kind.CONCRETE: "break_concrete",
	Materials.Kind.WOOD: "break_wood",
	Materials.Kind.METAL: "break_metal",
	Materials.Kind.ICE: "ice_hit",
	Materials.Kind.GLASS: "ice_break",
}

var _players: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _next := 0
var _next_ui := 0
var _last := {}  # name -> time of last start
var _started := PackedFloat64Array()  # per 3D player: when it last started


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
		_started.append(-1.0)
	for i in POOL_UI:
		var u := AudioStreamPlayer.new()
		add_child(u)
		_ui.append(u)
	_music = _loop_player("res://audio/music.ogg", MUSIC_DB)
	_ambience = _loop_player("res://audio/ambience.ogg", AMBIENCE_DB)


func _loop_player(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream := (load(path) as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	stream.loop = true
	p.stream = stream
	p.volume_db = db
	add_child(p)
	if DisplayServer.get_name() != "headless":
		p.play()
	return p


## Lowers the music for a moment so a big collapse is heard (it comes back
## over `back` seconds).
func duck(db := -9.0, back := 3.0) -> void:
	if _music == null:
		return
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", MUSIC_DB + db, 0.15)
	tw.tween_property(_music, "volume_db", MUSIC_DB, back)


## Plays a sound at a world position (Vector3.INF = not positional).
func play(sound: String, at := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void:
	if not SOUNDS.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -1.0)) < MIN_GAP:
		return
	# Only players still playing this very sound count toward its cap (a
	# pooled player may have moved on to another sound since).
	var stream: AudioStream = SOUNDS[sound]
	var alive := 0
	for p in _players:
		if p.playing and p.stream == stream:
			alive += 1
	if alive >= MAX_ALIVE:
		return
	_last[sound] = now
	if at == Vector3.INF:
		ui(sound, volume_db, pitch)
		return
	var k := _free_player()
	var p := _players[k]
	_started[k] = now
	p.stream = stream
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## A silent player if there is one, else the one that started longest ago
## (a short crack is cut, not a collapse that just began).
func _free_player() -> int:
	for n in POOL_3D:
		var k := (_next + n) % POOL_3D
		if not _players[k].playing:
			_next = (k + 1) % POOL_3D
			return k
	var oldest := 0
	for k in POOL_3D:
		if _started[k] < _started[oldest]:
			oldest = k
	return oldest


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
