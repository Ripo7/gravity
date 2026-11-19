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
## A house, on the brute's right as it starts: its eaves at the brute's
## shoulders, its ridge over its head. It is laid out straight, the middle
## of its floor at HOUSE_AT, and stands turned HOUSE_TURN degrees about
## the vertical there: askew, as buildings along a street that is not
## straight will stand. HOUSE across (x, as it is laid out) and along its
## ridge (z), between the outer faces of its corner posts.
## Its frame, in dark wood: four corner posts HOUSE_POST thick and
## HOUSE_WALL high; along the top of each long wall a plate, a beam PLATE
## high; in the middle of each gable a taller post, under the ridge beam;
## and on each slope a rafter at each of RAFTER_AT (along the ridge), which
## leans from the plate up to the ridge and goes EAVE m past the wall.
## The roof rises HOUSE_PITCH m a metre: BOARDS_A_SLOPE boards on each
## slope, laid along the ridge on the rafters, RAKE m past each gable.
## Its walls are planks CLAD thick that stand between the posts and carry
## nothing: they stop SLACK m short of what is over them. Each long wall
## is WALL_BAYS planks wide; a window takes two of them (planks up to
## SILL, a pane of glass on those), the door two more, in the wall that
## faces the start (-x). Each gable has GABLE_BAYS planks on each side of its
## post, which rise with the roof.
## And a porch over the door: a lean-to PORCH out from the wall and wide,
## of boards on two beams, on posts PORCH_HIGH high (at the wall, in
## front).
const HOUSE_AT := Vector3(7, 0, 2)
const HOUSE_TURN := -30.0
const HOUSE := Vector2(2.4, 3.0)
const HOUSE_POST := 0.14
const HOUSE_WALL := 1.5
const PLATE := 0.1
const HOUSE_PITCH := 0.577
const RIDGE := Vector2(0.14, 0.12)
const RAFTER := Vector2(0.1, 0.08)
const RAFTER_AT: Array[float] = [-1.55, -0.5, 0.5, 1.55]
const EAVE := 0.25
const RAKE := 0.2
const ROOF_BOARD := 0.04
const BOARDS_A_SLOPE := 4
const CLAD := 0.06
const SLACK := 0.04
const WALL_BAYS := 9
const FRONT := "PPWWPDDPP"
const BACK := "PWWPPPWWP"
const GABLE_BAYS := 4
const SILL := 0.55
const PANE_THICK := 0.04
const DOOR := 1.2
const PORCH := Vector2(0.75, 1.2)
const PORCH_POST := 0.1
const PORCH_HIGH := Vector2(1.27, 1.03)
## How much darker than plain wood its frame, its roof and its door are.
const FRAME_SHADE := 0.4
const ROOF_SHADE := 0.25
const DOOR_SHADE := 0.32

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
## The house. Its frame: the four corner posts, the two plates, the two
## posts under the ridge, the ridge beam, the rafters. Its roof boards.
## What it is clad in: the planks of its long walls (those under the
## windows too), the planks of its gables, its panes, its door. Its porch:
## four posts, two beams, three boards.
var house_posts := PackedInt32Array()
var house_plates := PackedInt32Array()
var house_ridge_posts := PackedInt32Array()
var house_ridge := -1
var house_rafters := PackedInt32Array()
var house_roof := PackedInt32Array()
var house_walls := PackedInt32Array()
var house_gables := PackedInt32Array()
var house_panes := PackedInt32Array()
var house_door := -1
var house_porch := PackedInt32Array()
## How the house is turned when the bench is laid (degrees, see HOUSE_TURN).
var house_turn := HOUSE_TURN


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
	structure.frame = house_frame()
	_lay_house()
	structure.frame = Transform3D.IDENTITY
	structure.build()


## Where the house stands and how it is turned: what takes a point of the
## house as it is laid out (see HOUSE), from the middle of its floor, to
## where it is on the bench.
func house_frame() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(house_turn)), HOUSE_AT)


## The house (see HOUSE), laid out straight round the middle of its floor,
## in the frame of the structure. The underside of its rafters is one
## plane on each side, which passes over the outer edge of the top of the
## plate and over the edge of the ridge beam; the roof boards lie on the
## top of the rafters.
func _lay_house() -> void:
	var half := HOUSE * 0.5
	var slope := atan(HOUSE_PITCH)
	var plate_top := HOUSE_WALL + PLATE
	for group: PackedInt32Array in [
		house_posts,
		house_plates,
		house_ridge_posts,
		house_rafters,
		house_roof,
		house_walls,
		house_gables,
		house_panes,
		house_porch
	]:
		group.clear()
	# The frame: corner posts, and a plate along each long wall on two of
	# them (it goes on under the rafters at the two ends).
	var post := Vector3(HOUSE_POST, HOUSE_WALL, HOUSE_POST)
	for side: float in [-1.0, 1.0]:
		var x := side * (half.x - HOUSE_POST * 0.5)
		for end: float in [-1.0, 1.0]:
			var foot := Vector3(x, 0, end * (half.y - HOUSE_POST * 0.5))
			house_posts.append(_stand(Matter.WOOD, post, foot, FRAME_SHADE))
		var plate := Vector3(HOUSE_POST, PLATE, HOUSE.y + 2.0 * RAFTER.x)
		house_plates.append(_stand(Matter.WOOD, plate, Vector3(x, HOUSE_WALL, 0), FRAME_SHADE))
	# The ridge beam, on a post in the middle of each gable.
	var ridge_top := plate_top + (half.x - RIDGE.x * 0.5) * HOUSE_PITCH
	for end: float in [-1.0, 1.0]:
		var foot := Vector3(0, 0, end * (half.y - HOUSE_POST * 0.5))
		var tall := Vector3(HOUSE_POST, ridge_top - RIDGE.y, HOUSE_POST)
		house_ridge_posts.append(_stand(Matter.WOOD, tall, foot, FRAME_SHADE))
	var ridge := Vector3(RIDGE.x, RIDGE.y, HOUSE.y + 2.0 * RAKE)
	house_ridge = _stand(Matter.WOOD, ridge, Vector3.UP * (ridge_top - RIDGE.y), FRAME_SHADE)
	# The roof, one slope then the other: rafters from just short of the
	# middle to past the wall, then the boards across them.
	var out := half.x + EAVE
	for side: float in [-1.0, 1.0]:
		var turn := Basis(Vector3.BACK, -side * slope)
		var from := 0.01
		var middle := (from + out) * 0.5
		var under := Vector3(side * middle, plate_top + (half.x - middle) * HOUSE_PITCH, 0)
		var rafter := Vector3((out - from) / cos(slope), RAFTER.y, RAFTER.x)
		for z in RAFTER_AT:
			var xf := Transform3D(turn, under + Vector3(0, 0, z) + turn.y * RAFTER.y * 0.5)
			house_rafters.append(structure.add_piece(Matter.WOOD, xf, rafter, FRAME_SHADE))
		from = 0.03
		var wide := (out - from) / BOARDS_A_SLOPE
		var board := Vector3(wide / cos(slope), ROOF_BOARD, HOUSE.y + 2.0 * RAKE)
		for k in BOARDS_A_SLOPE:
			middle = from + (k + 0.5) * wide
			under = Vector3(side * middle, plate_top + (half.x - middle) * HOUSE_PITCH, 0)
			var lift := RAFTER.y + ROOF_BOARD * 0.5
			var xf := Transform3D(turn, under + turn.y * lift)
			house_roof.append(structure.add_piece(Matter.WOOD, xf, board, ROOF_SHADE))
	# The long walls, between the corner posts: planks, windows, the door.
	var bay := (HOUSE.y - 2.0 * HOUSE_POST) / WALL_BAYS
	var high := HOUSE_WALL - SLACK
	var door_at := 0.0
	for side: float in [-1.0, 1.0]:
		var plan := FRONT if side < 0.0 else BACK
		var x := side * (half.x - CLAD * 0.5)
		for k in WALL_BAYS:
			var z := (k - (WALL_BAYS - 1) * 0.5) * bay
			var pair := k > 0 and plan[k] == plan[k - 1]
			if plan[k] == "P":
				house_walls.append(_stand(Matter.WOOD, Vector3(CLAD, high, bay), Vector3(x, 0, z)))
			elif plan[k] == "W":
				house_walls.append(_stand(Matter.WOOD, Vector3(CLAD, SILL, bay), Vector3(x, 0, z)))
				if pair:
					var pane := Vector3(PANE_THICK, high - SILL, 2.0 * bay)
					house_panes.append(_stand(Matter.GLASS, pane, Vector3(x, SILL, z - bay * 0.5)))
			elif pair:
				door_at = z - bay * 0.5
				var door := Vector3(PANE_THICK, DOOR, 2.0 * bay)
				house_door = _stand(Matter.WOOD, door, Vector3(x, 0, door_at), DOOR_SHADE)
	# The gables, between the corner posts and the post in the middle:
	# each plank as high as the roof boards let it be at its outer edge.
	var across := (half.x - HOUSE_POST * 1.5) / GABLE_BAYS
	for end: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			for k in GABLE_BAYS:
				var outer := HOUSE_POST * 0.5 + (k + 1) * across
				var top := plate_top + (half.x - outer) * HOUSE_PITCH + RAFTER.y / cos(slope) - SLACK
				var foot := Vector3(side * (outer - across * 0.5), 0, end * (half.y - CLAD * 0.5))
				house_gables.append(_stand(Matter.WOOD, Vector3(across, top, CLAD), foot))
	# The porch, over the door: two posts at the wall and two lower ones in
	# front, a beam on each pair, boards that lean from one to the other.
	var reach := PORCH.x - PORCH_POST
	var fall_off := (PORCH_HIGH.x - PORCH_HIGH.y) / reach
	for row in 2:
		var x := -(half.x + PORCH_POST * 0.5 + row * reach)
		var tall: float = PORCH_HIGH[row]
		for end: float in [-1.0, 1.0]:
			var foot := Vector3(x, 0, door_at + end * (PORCH.y - PORCH_POST) * 0.5)
			var leg := Vector3(PORCH_POST, tall, PORCH_POST)
			house_porch.append(_stand(Matter.WOOD, leg, foot, FRAME_SHADE))
	for row in 2:
		var x := -(half.x + PORCH_POST * 0.5 + row * reach)
		var beam := Vector3(PORCH_POST, PORCH_POST, PORCH.y + 0.1)
		house_porch.append(_stand(Matter.WOOD, beam, Vector3(x, PORCH_HIGH[row], door_at), FRAME_SHADE))
	var lean := Basis(Vector3.BACK, atan(fall_off))
	var far := half.x + PORCH.x + 0.08
	var mid := (half.x + far) * 0.5
	var lies := Vector3(-mid, PORCH_HIGH.x + PORCH_POST - (mid - half.x - PORCH_POST) * fall_off, door_at)
	var plank := Vector3((far - half.x) / cos(atan(fall_off)), ROOF_BOARD, (PORCH.y + 0.1) / 3.0)
	for k in 3:
		var xf := Transform3D(lean, lies + Vector3(0, 0, (k - 1) * plank.z) + lean.y * ROOF_BOARD * 0.5)
		house_porch.append(structure.add_piece(Matter.WOOD, xf, plank, ROOF_SHADE))


## Every piece of the house.
func house_pieces() -> PackedInt32Array:
	var all := PackedInt32Array([house_ridge, house_door])
	for group: PackedInt32Array in [
		house_posts,
		house_plates,
		house_ridge_posts,
		house_rafters,
		house_roof,
		house_walls,
		house_gables,
		house_panes,
		house_porch
	]:
		all.append_array(group)
	return all


## A piece made `of` a matter, `size` across, its foot at `foot` (in the
## frame of the structure), drawn `shade` darker than its matter. Returns
## its number.
func _stand(of: int, size: Vector3, foot: Vector3, shade := 0.0) -> int:
	var middle := Transform3D(Basis(), foot + Vector3.UP * size.y * 0.5)
	return structure.add_piece(of, middle, size, shade)


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
