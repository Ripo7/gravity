class_name Hud
extends Control
## What is drawn over the game: a line of numbers (frames per second, the
## cost of a physics step, what stands and what lies loose, which build this
## is), what the controls are, the slider that sets how fast things fall,
## and the button that puts the bench back as it was.

signal rebuild_pressed
## The slider was moved: the share of real gravity that pulls what has come
## off.
signal fall_set(share: float)

## The controls are shown for this long (s), then fade.
const HINT_FOR := 8.0

var world: Main

var _stats: Label
var _build: String = ProjectSettings.get_setting("application/config/version", "")
var _hint: Label
var _fall: HSlider
var _fall_says: Label
var _since := 0.0
var _shown := 0.0


## Where the rebuild button sits on a screen of `view` size.
static func rebuild_rect(view: Vector2) -> Rect2:
	return Rect2(view.x - 196.0, 16.0, 180.0, 56.0)


## Where the slider that sets how fast things fall sits, with what it says.
static func fall_rect(view: Vector2) -> Rect2:
	return Rect2(view.x - 600.0, 8.0, 380.0, 84.0)


## Is `at`, on a screen of `view` size, on something of the HUD that takes
## touches (so that the thumbs' controls leave it alone)?
static func takes(at: Vector2, view: Vector2) -> bool:
	return rebuild_rect(view).grow(10).has_point(at) or fall_rect(view).grow(10).has_point(at)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats = _label(18)
	_stats.position = Vector2(20, 14)
	_hint = _label(22)
	_hint.position = Vector2(20, 44)
	_hint.text = (
		"Clic ou F : frapper  ·  Clic droit ou E : coup de pied\n"
		+ "Espace : sauter  ·  Maj : sprinter  ·  R : reconstruire"
	)
	if TouchControls.should_show():
		_hint.text = "Rouge : frapper  ·  Orange : coup de pied\nManette poussée à fond : sprint"
	var button := Button.new()
	button.text = "Reconstruire"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	add_child(button)
	button.pressed.connect(func() -> void: rebuild_pressed.emit())
	_fall_says = _label(18)
	_fall = HSlider.new()
	_fall.min_value = Rubble.FALL_LEAST
	_fall.max_value = Rubble.FALL_MOST
	_fall.step = 0.05
	_fall.value = world.fall if world != null else Rubble.FALL
	_fall.focus_mode = Control.FOCUS_NONE
	add_child(_fall)
	_fall.value_changed.connect(_on_fall_changed)
	_on_fall_changed(_fall.value)
	var place := func() -> void:
		var r := rebuild_rect(size)
		button.position = r.position
		button.size = r.size
		var f := fall_rect(size)
		_fall_says.position = f.position
		# (Tall, for a thumb.)
		_fall.position = f.position + Vector2(0, 24)
		_fall.size = Vector2(f.size.x, f.size.y - 24)
	resized.connect(place)
	place.call()


func _on_fall_changed(share: float) -> void:
	_fall_says.text = "Chute : %.2f  (gauche : lente, droite : rapide)" % share
	fall_set.emit(share)


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.12))
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	return l


func _process(delta: float) -> void:
	_since += delta
	_shown += delta
	if _since < 0.25 or world == null:
		return
	_since = 0.0
	var s := world.structure
	_stats.text = (
		"%d i/s   physique %.1f ms   debout %d/%d   morceaux %d (%d bougent)   v%s"
		% [
			Engine.get_frames_per_second(),
			world.clock.avg_ms,
			s.standing_count,
			s.pieces,
			s.rubble.live,
			s.rubble.awake,
			_build
		]
	)
	_hint.modulate.a = move_toward(_hint.modulate.a, 0.0 if _shown > HINT_FOR else 1.0, 0.25)
