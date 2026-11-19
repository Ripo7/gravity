class_name Main
extends Node3D
## The test bench, in greybox: a bare ground, one giant brute, yours, seen
## in third person, and a few pieces of each matter for it to break. What
## breaks is worked out here one matter at a time (docs/CONCEPT.md):
## concrete on its right as it starts, metal on its left, wood straight
## ahead, farther off, glass behind it.

## Where the brute starts.
const START := Vector3(0, 0.05, 0)
## The ground is this wide (m).
const GROUND := 400.0
## What stands on the bench, in concrete. A column on its own; a wall, in
## one piece (wide enough to have a hole knocked in it); a slab on four
## columns, SPAN m apart.
const COLUMN := Vector3(0.4, 2.6, 0.4)
const COLUMN_AT := Vector3(1.5, 0, -6)
const WALL := Vector3(3.6, 2.4, 0.35)
const WALL_AT := Vector3(4.5, 0, -8)
const POST := Vector3(0.4, 2.2, 0.4)
const SLAB := Vector3(3.6, 0.3, 3.6)
const SLAB_AT := Vector3(9, 0, -7.5)
const SPAN := 3.2
## And in metal, the same three things: a post on its own; a fence of
## SHEETS sheets side by side; a deck on four posts.
const METAL_POST := Vector3(0.2, 2.6, 0.2)
const METAL_POST_AT := Vector3(-1.5, 0, -6)
const SHEET := Vector3(1.2, 2.4, 0.08)
const SHEETS := 3
const FENCE_AT := Vector3(-4.5, 0, -8)
const PIER := Vector3(0.2, 2.2, 0.2)
const DECK := Vector3(3.6, 0.12, 3.6)
const DECK_AT := Vector3(-9, 0, -7.5)
## And in wood, straight ahead: a post on its own; a palisade of PLANKS
## planks that stand side by side, each a piece; a floor of BOARDS boards
## laid across two beams on four posts.
const WOOD_POST := Vector3(0.2, 2.6, 0.2)
const WOOD_POST_AT := Vector3(0, 0, -10)
const PLANK := Vector3(0.3, 2.4, 0.06)
const PLANKS := 10
const PALISADE_AT := Vector3(0, 0, -13)
const STILT := Vector3(0.2, 2.0, 0.2)
const BEAM := Vector3(0.2, 0.2, 3.2)
const BOARD := Vector3(3.2, 0.06, 0.4)
const BOARDS := 8
const FLOOR_AT := Vector3(0, 0, -19)
const FLOOR_SPAN := 2.8
## And in glass, behind the brute as it starts: PANES panes side by side.
const PANE := Vector3(1.2, 2.4, 0.04)
const PANES := 3
const GLASS_AT := Vector3(0, 0, 8)
## A house, in wood, on the brute's right as it starts: as tall as the
## brute is. HOUSE across (x) and along its ridge (z). Walls of planks that
## stand side by side, each a piece: the two long ones HOUSE_WALL high,
## with a doorway DOOR planks wide in the one that faces the start, and
## the two gables, which rise with the roof. A roof of two slopes, which
## rises HOUSE_PITCH m a metre: BOARDS_A_SLOPE boards on each side, tilted,
## from the top of a long wall up to the ridge beam, which the gables
## carry. No eaves: a straight finds the wall, not the edge of the roof.
const HOUSE_AT := Vector3(7, 0, 2)
const HOUSE := Vector2(2.4, 3.0)
const HOUSE_WALL := 1.45
const HOUSE_PITCH := 0.375
const HOUSE_PLANK := Vector2(0.3, 0.06)
const HOUSE_DOOR := 2
const GABLE_PLANKS := 8
const RIDGE := Vector2(0.16, 0.12)
const ROOF_BOARD := Vector2(0.5, 0.05)
const BOARDS_A_SLOPE := 6

var player: Player
var structure: Structure
var clock: PhysicsClock
var hud: Hud
## The share of real gravity that pulls what has come off (see Rubble):
## set on the screen, kept when the bench is put back.
var fall := Rubble.FALL:
	set = set_fall
## On the bench, in concrete: the column that stands alone, the wall, the
## four columns under the slab, the slab (the numbers of their pieces).
var column := -1
var wall := -1
var posts := PackedInt32Array()
var slab := -1
## And in metal: the post that stands alone, the sheets of the fence, the
## four posts under the deck, the deck.
var metal_post := -1
var sheets := PackedInt32Array()
var piers := PackedInt32Array()
var deck := -1
## And in wood: the post that stands alone, the planks of the palisade,
## the four posts under the floor, its two beams, its boards.
var wood_post := -1
var planks := PackedInt32Array()
var stilts := PackedInt32Array()
var beams := PackedInt32Array()
var boards := PackedInt32Array()
## And in glass: the panes.
var panes := PackedInt32Array()
## The house: the planks of its two long walls, those of its two gables,
## its ridge beam, the boards of its roof.
var house_walls := PackedInt32Array()
var house_gables := PackedInt32Array()
var house_ridge := -1
var house_roof := PackedInt32Array()


func _ready() -> void:
	clock = PhysicsClock.new()
	add_child(clock)
	var options: Dictionary = get_node("/root/Launch").options
	_build_world()
	player = Player.new()
	add_child(player)
	player.global_position = START
	player.blow.connect(_on_blow)
	_lay_bench()
	add_child(BlobShadow.new(player))
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = self
	ui.add_child(hud)
	hud.rebuild_pressed.connect(rebuild)
	hud.fall_set.connect(set_fall)
	if TouchControls.should_show():
		var touch := TouchControls.new()
		touch.player = player
		ui.add_child(touch)
	print("BENCH ready: %d pieces, %d parts" % [structure.pieces, structure.count])
	if options.has("mode"):
		var director := Director.new()
		director.options = options
		add_child(director)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rebuild"):
		rebuild()


func set_fall(share: float) -> void:
	fall = clampf(share, Rubble.FALL_LEAST, Rubble.FALL_MOST)
	if structure != null:
		structure.rubble.fall = fall


## Puts the bench back as it was, and the brute where it started.
func rebuild() -> void:
	structure.free()
	_lay_bench()
	player.global_position = START
	player.velocity = Vector3.ZERO


func _on_blow(at: Vector3, way: Vector3, power: int, on: RID) -> void:
	structure.strike(at, way, power, on)


## What stands on the bench: in concrete, a column, a wall, a slab on four
## columns; in metal, a post, a fence of sheets, a deck on four posts; in
## wood, a post, a palisade of planks, a floor of boards on two beams on
## four posts; in glass, three panes.
func _lay_bench() -> void:
	structure = Structure.new()
	add_child(structure)
	structure.rubble.fall = fall
	# What comes down on the brute pushes it out of the way.
	structure.rubble.brute = player
	structure.rubble.bears_down.connect(player.give_way)
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	column = _stand(Matter.CONCRETE, COLUMN, COLUMN_AT)
	metal_post = _stand(Matter.METAL, METAL_POST, METAL_POST_AT)
	wall = _stand(Matter.CONCRETE, WALL, WALL_AT)
	sheets.clear()
	for k in SHEETS:
		var along := Vector3((k - (SHEETS - 1) * 0.5) * SHEET.x, 0, 0)
		sheets.append(_stand(Matter.METAL, SHEET, FENCE_AT + along))
	posts.clear()
	piers.clear()
	for corner in corners:
		var out := Vector3(corner.x, 0, corner.y) * SPAN * 0.5
		posts.append(_stand(Matter.CONCRETE, POST, SLAB_AT + out))
		piers.append(_stand(Matter.METAL, PIER, DECK_AT + out))
	slab = _stand(Matter.CONCRETE, SLAB, SLAB_AT + Vector3.UP * POST.y)
	deck = _stand(Matter.METAL, DECK, DECK_AT + Vector3.UP * PIER.y)
	wood_post = _stand(Matter.WOOD, WOOD_POST, WOOD_POST_AT)
	planks.clear()
	for k in PLANKS:
		var along := Vector3((k - (PLANKS - 1) * 0.5) * PLANK.x, 0, 0)
		planks.append(_stand(Matter.WOOD, PLANK, PALISADE_AT + along))
	stilts.clear()
	beams.clear()
	boards.clear()
	for corner in corners:
		var out := Vector3(corner.x, 0, corner.y) * FLOOR_SPAN * 0.5
		stilts.append(_stand(Matter.WOOD, STILT, FLOOR_AT + out))
	# A beam on each side, from front to back; the boards across them.
	for side: float in [-1.0, 1.0]:
		var out := Vector3(side * FLOOR_SPAN * 0.5, STILT.y, 0)
		beams.append(_stand(Matter.WOOD, BEAM, FLOOR_AT + out))
	for k in BOARDS:
		var along := Vector3(0, STILT.y + BEAM.y, (k - (BOARDS - 1) * 0.5) * BOARD.z)
		boards.append(_stand(Matter.WOOD, BOARD, FLOOR_AT + along))
	panes.clear()
	for k in PANES:
		panes.append(_stand(Matter.GLASS, PANE, GLASS_AT + Vector3((k - (PANES - 1) * 0.5) * PANE.x, 0, 0)))
	_lay_house(HOUSE_AT)
	structure.build()


## The house, the middle of its floor at `at` (see HOUSE). The underside of
## its roof is one plane on each side: it passes over the outer edge of the
## top of the long wall, and over the edge of the ridge beam.
func _lay_house(at: Vector3) -> void:
	var half := HOUSE * 0.5
	var thick := HOUSE_PLANK.y
	house_walls.clear()
	house_gables.clear()
	house_roof.clear()
	# The long walls: planks side by side along the ridge. The doorway is
	# in the middle of the one that faces the start (-x).
	var along := roundi(HOUSE.y / HOUSE_PLANK.x)
	for side: float in [-1.0, 1.0]:
		for k in along:
			if side < 0.0 and absi(2 * k - (along - 1)) < HOUSE_DOOR:
				continue
			var foot := Vector3(side * (half.x - thick * 0.5), 0, (k - (along - 1) * 0.5) * HOUSE_PLANK.x)
			house_walls.append(_stand(Matter.WOOD, Vector3(thick, HOUSE_WALL, HOUSE_PLANK.x), at + foot))
	# The gables, between the long walls: each plank as high as the roof
	# lets it be at its outer edge; the two in the middle carry the ridge.
	var ridge_top := HOUSE_WALL + (half.x - RIDGE.x * 0.5) * HOUSE_PITCH
	var across := (HOUSE.x - 2.0 * thick) / GABLE_PLANKS
	for side: float in [-1.0, 1.0]:
		for k in GABLE_PLANKS:
			var x := (k - (GABLE_PLANKS - 1) * 0.5) * across
			var high := HOUSE_WALL + (half.x - absf(x) - across * 0.5) * HOUSE_PITCH
			high = minf(high, ridge_top - RIDGE.y)
			var foot := Vector3(x, 0, side * (half.y - thick * 0.5))
			house_gables.append(_stand(Matter.WOOD, Vector3(across, high, thick), at + foot))
	house_ridge = _stand(
		Matter.WOOD, Vector3(RIDGE.x, RIDGE.y, HOUSE.y), at + Vector3.UP * (ridge_top - RIDGE.y)
	)
	# The roof: boards that lean on the long walls and the ridge, their
	# lower end over the outer edge of the wall, their upper end just
	# short of the middle.
	var slope := atan(HOUSE_PITCH)
	var top := RIDGE.x * 0.125
	var long := (half.x - top) / cos(slope)
	for side: float in [-1.0, 1.0]:
		var turn := Basis(Vector3.BACK, -side * slope)
		var out := (half.x + top) * 0.5
		var under := Vector3(side * out, HOUSE_WALL + (half.x - out) * HOUSE_PITCH, 0)
		for k in BOARDS_A_SLOPE:
			var z := (k - (BOARDS_A_SLOPE - 1) * 0.5) * ROOF_BOARD.x
			var middle := at + under + Vector3(0, 0, z) + turn.y * ROOF_BOARD.y * 0.5
			house_roof.append(
				structure.add_piece(
					Matter.WOOD, Transform3D(turn, middle), Vector3(long, ROOF_BOARD.y, ROOF_BOARD.x)
				)
			)


## A piece made `of` a matter, `size` across, its foot at `foot`. Returns
## its number.
func _stand(of: int, size: Vector3, foot: Vector3) -> int:
	var middle := Transform3D(Basis(), foot + Vector3.UP * size.y * 0.5)
	return structure.add_piece(of, middle, size)


func _build_world() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.2, 0.45, 0.9)
	sky.sky_horizon_color = Color(0.7, 0.85, 0.98)
	sky.ground_horizon_color = Color(0.7, 0.85, 0.98)
	sky.ground_bottom_color = Color(0.3, 0.34, 0.4)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky
	# (Lit by the sky alone, everything would turn blue.)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.95)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	# The sun casts no shadow: on the phone this was measured on, its
	# shadows were what cost the most (docs/PERFORMANCE.md). The brute has
	# a round one at its feet (BlobShadow).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.75
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = false
	add_child(sun)

	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND, GROUND)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground.gdshader")
	plane.material = mat
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var ground_shape := CollisionShape3D.new()
	ground_shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(ground_shape)
	var ground_look := MeshInstance3D.new()
	ground_look.mesh = plane
	ground_look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(ground_look)
	add_child(ground)
