# Architecture

How the code is laid out and who owns what. What the game is to be is in
[CONCEPT.md](CONCEPT.md); numbers are in [PERFORMANCE.md](PERFORMANCE.md);
where the assets come from is in [CREDITS.md](../CREDITS.md).

The game is at step 3 of its plan: a bench, one brute, and concrete and
metal to break. The engine of the version before (boxes cut into shards bonded
together) was taken out, on purpose: see the end of the concept for why,
and the branch `archive/v1` for the code.

## Layout

| Where | What |
| --- | --- |
| `scripts/main.gd` | builds the bench: sky, sun, ground, what stands on it, the brute, HUD |
| `scripts/core/` | launch options, input map, collision layers, the physics clock, scripted runs (`director.gd`) |
| `scripts/player/` | `Player` (controls, camera) and `Character` (the animated body) |
| `scripts/fx/` | the round shadow under the brute |
| `scripts/ui/` | HUD and touch controls |
| `scripts/destruction/` | what breaks: `Matter`, `Structure` (what stands), `Bend` (how a piece of metal is bent), `Rubble` (what has come off), `Fracture` (the cut), `ShardMesh` (the picture) |
| `shaders/` | the ground's grid; the one shader that draws everything that stands or has come off |
| `assets/` | the mannequin and its blows (made by `tools/moves`) |
| `tools/` | CI and build scripts, the web probe, the asset tools |
| `tests/` | headless tests, one file per subject |

Everything is built in code: there are two scenes, `scenes/main.tscn` (one
node with `main.gd`) and the test runner's.

## Who owns what

- **`Main`** creates everything and hands each part what it needs.
  Nothing looks its neighbours up by path.
- **`Player`** is the brute as you steer it: it reads the keys, the
  gamepad and the thumbs (`TouchControls` sets its `touch_*`), moves the
  capsule and places the camera.
- **`Character`** is a body you see and nothing else: it is told what
  happens (`move`, `jump`, `land`, `punch`) and turns it into a pose.
  It says when a strike starts (`swung`), where its fist is drawn at
  each step while it is thrown (`reached`, `limb`), and how hard the
  blow is (`power`). It never decides what the blow does.
- **`Player`** follows that fist and says where it first touched
  something, what, and how hard (`blow`); **`Main`** hands it to the
  structure (`Structure.strike`). The brute knows nothing of what it
  breaks.
- **`Structure`** owns what stands, its blocks and the `Rubble`. The
  rest of the game breaks things through `strike` (a blow of the brute)
  and `hit` (so many points of blows to a piece).
- Signals go up, calls go down; a child never calls its parent.

Collision layers (`Layers`): 1 world (the ground, what neither moves nor
breaks), 2 structure (what stands: in the way of the brute and of the
camera), 3 rubble (what has come off: in the way of the brute, not of
the camera), 4 the brute.

## Conventions

- GDScript is typed everywhere; the warnings a reviewer would send back
  (untyped, unused, shadowed, unreachable) are errors in `project.godot`,
  so a script with one does not load and the tests fail.
- `gdlint` and `gdformat` decide the style; class order is constants,
  variables, then functions.
- Every tuning number is a named constant with a comment that says what
  it means and its unit.
- Comments say why. A claim about speed or cost comes with a measurement.
- Scripted, seeded runs (`--mode=play`) are how clips and numbers are
  made, so both can be made again.
- Nothing is kept that nothing uses.

## What breaks

The rule is in the concept: a building is an assembly of simple pieces,
each of one matter, and the matter alone says how a piece answers a
blow. Four matters: concrete, which breaks; wood, which snaps; metal,
which bends; glass, which bursts.

### What all matters share

1. **Pieces** (`Structure.add_piece`). A piece is a box: a column, a
   slab, a wall, a plank. It stands upright or lies flat; one that lies
   flat may be tilted (a rafter, a board of a roof). While it stands
   whole it is one static box for the physics.
2. **A blow harms the place it lands on**, not the whole piece. What a
   place takes belongs to the piece (`Matter.strength`): so many points
   of blows for each metre the piece is thick the way it is thinnest,
   22.5 for concrete, so 9 for a column 0.4 m thick; 70 for metal, so 14
   for a post 0.2 m thick. A blow is 2 points, a heavy one (the last of
   the combination) 3. How the piece is cut or drawn changes
   nothing to it.
3. **What is no longer carried comes down** (`Structure._settle`). A
   piece rests on the pieces right under it. When something under it
   goes, what is left of it is looked at again, and so on up through
   what rests on it. A slab or a metal piece holds if it stands on the
   ground or if its middle is still over what is left under it (a slab
   holds on three columns, not on two on the same side: `_held`);
   otherwise it comes down in one, a loose body. (A wall or a column is
   looked at block by block, and a metal plate sags: see below.) A
   tilted piece rests on the pieces its underside passes over at the
   height of their top (`Structure.build`, `_face_at`): a rafter, on the
   plate under its lower end and on the ridge beam under its upper end;
   a board, on the rafters. It is held like a slab, by where its middle
   is over them seen from above.
4. **Only a blow breaks or bends.** From the brute: the blow lands
   where its fist or foot first touches something (see "Where a blow
   lands" below); that takes it, there (`Structure.strike`), and what
   lies loose near there is sent off (not far: it is heavy). Or from
   something heavy that lands
   on a piece (`Rubble._land`): a point for each 900 kg.m/s it loses
   against it, where it lands, and only on a face that looks up. What
   brushes past a wall on its way down does nothing to it. Walking,
   running and jumping break nothing: what stands is a wall to the
   brute.
5. **The rubble** (`Rubble`). Loose bodies are made straight on the
   physics server, no nodes. They fall at a share of real gravity
   (`fall`, set by the slider): all of it to begin with, which is what
   the owner settled on, on the phone; less was tried, to make the brute
   a giant. Speeds told "as at real gravity" in the code go with the
   square root of that share, so the same things happen at any setting,
   only slower. A body that touches something and has been
   still for half a second is frozen (static): a heap costs nothing,
   stays put, and the brute steps onto it. It moves again when a piece
   near it breaks or when a blow lands by it. Nothing rests on the brute
   itself: what comes down on it pushes it out from under
   (`Rubble.bears_down`, `Player.give_way`). And its body throws
   nothing: near it, no loose body goes sideways faster than 6.5 m/s nor
   up faster than 1.5 (`Rubble.PUSH`, `LIFT`). A sheet propped against
   the brute and pushed at its foot left for the sky at 17 m/s before
   that.
6. **One draw call** (`ShardMesh`, `shaders/shards.gdshader`). Everything
   is in one mesh that never changes; a small texture says which body
   each part goes with (and how far it is pushed in, for a dent) and
   another where each body is.

### Concrete: it cracks where it is struck, then lets go there

1. **Cut once, when it is made** (`Fracture`, `Matter.grain`). Each piece
   is cut into irregular convex blocks. A wall or a column takes blows:
   its blocks are about 0.4 m across, small enough for what a blow
   knocks out to be round the fist (6 for the column, 54 for the wall).
   A slab only comes down: about 0.9 m (16). Bigger, both, if that would
   make more than sixty. (With blocks 0.7 m across, the block a fist
   landed on went whole: the hole was under the fist, down to the
   ground.)
2. **Places** (`Structure.hit`, `_wound`). A blow lands on a place: one
   the piece has been struck at within 0.45 m of there, or a new one.
   What the place has taken is what counts, not what the piece has taken
   in all. The blocks round it (the nearest, and those whose middle is
   within 0.45 m) show cracks (`_crack`): each is drawn a little smaller
   and askew, the gaps dark, wider from half the strength on. The others
   show nothing.
3. **Letting go** (`Structure._expel`). When the place has taken what the
   piece can take, those blocks are knocked out, away from the blow, at
   3.5 m/s as at real gravity: loose bodies, and a hole about 0.9 m
   across where the fist landed. For half a
   second what is left of the piece does not stop them (`Rubble.
   let_through`): cut every which way, a block would stay caught in its
   hole. From under something the piece carried, they hardly rub on
   anything for 0.45 s and slide out (`Rubble.slip`). What stands of the
   piece is, from then on, the blocks that are left, each in the way as
   it is (`_refresh`).
4. **What holds** (`Structure._unheld`, for a wall or a column). A block
   holds if it sits on something: the ground or what stands under the
   piece, or the block right under it, if that one sits. Or if it is in
   a row of blocks, side by side, between two that sit no more than
   1.25 m apart: the lintel over the hole of one blow. Over a wider hole
   what is left comes down: holes side by side open a wall to the top.
   Which block is right under and which are right beside which is worked
   out once, when the piece is cut (`_lay_courses`).
5. **Coming down in one** (`Structure._fall`, `break_up`). What no
   longer holds comes down as one loose body, the blocks that hold
   together through their cuts. Cut off by a blow, it starts off going
   over away from it. It breaks into its blocks when something stops it
   once it has come down 0.3 m. A slab that loses its columns comes down
   the same way, whole. (Stopped: it lost speed in a step in which it
   touched something. The engine can tell of the contacts a step before
   it tells what they took; the stop counts all the same, shared out
   evenly among them. Until 19 November such a landing was dropped, and
   a length of wall could be left lying whole.)
6. **All at once** (`Structure.shatter`). A blow that lands nowhere in
   particular (`hit` without a place: the measure, some tests) is taken
   by the whole piece, which cracks all over and, at its strength, goes
   over and comes apart, as every piece did before places.

### Wood: it snaps where it is struck

Wood is cut and held like concrete (the same blocks, places, falls);
what differs is in `Matter`, by matter:

1. **Lengths** (`Matter.grain`). A piece of wood is cut across its
   grain, the way it is longest, into lengths of about 0.4 m, whichever
   way it lies: 6 for a plank or a post, 8 for a beam or a board. The
   cuts lean, as they do in anything thin.
2. **At the first blow** (`Matter.STRENGTH`). 8 points for each metre
   it is thick: 1.6 for a post 0.2 m thick, 0.48 for a plank. A blow is
   2.
3. **Where the blow lands** (`Matter.PLACE`). A place of wood is 0.22 m
   across each way: the length the blow lands on goes, knocked out at
   6 m/s (`Matter.KNOCK`; concrete: 3.5). Each plank is a piece, and a
   blow lands on one body: it snaps the plank it touches, not the ones
   beside it.
4. **Cut off, thrown** (`Matter.THROWN`). What was above the blow is no
   longer held: it comes off in one, as a cut column does, and is thrown
   along the blow at 5.5 m/s on top of going over (concrete only goes
   over). A plank 13 kg lands 5 m away.
5. **Long pieces** (`Matter.SHATTERS`, `Structure.lands`). What comes
   down in one does not break when it lands: only concrete does. Struck
   where it lies, with what its piece can take (one blow), it comes
   apart into its lengths.
6. **Light** (`Rubble.LIGHT`). What weighs 40 kg or less is flung by a
   blow that lands near it: 6 m/s at most (2.5 for what is heavier).
   Nothing was added for the brute to walk through small wood: its body
   pushes what lies loose, as before.
7. **It carries.** A beam rests on two posts, a board on two beams
   (`_held`: its middle over what is left under it). A post cut under a
   beam: the beam comes down, whole, then every board that lay on it.

### Glass: it bursts, the whole pane

1. **One block** (`Matter.grain`). A piece of glass is not cut: it is
   its own box, a wall to the brute like any other while it stands.
2. **At the first blow, wherever it lands** (`Matter.BURSTS`,
   `Structure._burst`). Any blow at all, from the brute or from
   something heavy that lands on it, and the piece is gone: no longer
   drawn, no longer in anything's way. The pieces beside it take
   nothing.
3. **Glitter, not pieces** (`Glitter`, `shaders/glitter.gdshader`). What
   it turns into are small flat bits, 45 for each square metre of pane
   (200 at most), that start where the pane stood, fall straight down
   as fast as things fall on the bench, lie where they land 1.2 s and
   shrink away in 0.6 s. They are not bodies: nothing runs into them,
   nothing piles up on them, and the physics knows nothing of them. One
   multimesh for each pane that bursts, each bit placed by the shader
   from how long ago that was (one number sent to it each frame); it is
   freed once its last bit is gone.
4. **It carries nothing.** Nothing rests on glass on the bench. (Glass
   that loses what it stands on is not handled.)

### Metal: a blow leaves its mark where it lands

Metal never breaks. What a blow does to it depends on the shape of the
piece (`Bend`): a post, a sheet or a plate.

1. **A skin, not blocks** (`Bend.draw`, `ShardMesh.add_skin`,
   `add_face`). A piece that bends is drawn as a skin stretched between
   points that move: the rings of a post, 0.3 m apart; the nodes of a
   sheet, 0.2 m apart; the corners of the triangles of a plate. Moving
   them bends it without a gap; its faces are lit by how they lie now.
2. **A post kinks** (`Bend._kink`). Upright and no wider than 0.5 m. A
   blow is added, as an arrow along it as long as its points, to the
   kink at the height it lands at: a new one, or the one the post has
   within 0.5 m of there (three at most). So a kink goes away from the
   blow, deeper at each one, and a blow from the other side takes as
   much back. A post that stands free leans from each kink up, by up to
   1.25 rad at a kink that has taken all it can, the turn coming on over
   a metre; one that carries something keeps its head where it is and
   bows instead, up to 0.55 m aside (`Bend.ring_poses`). While it stands
   kinked, the brute and the camera meet it where it is: a box between
   its foot, its kinks and its head (`Structure._limbs_of`).
3. **A sheet takes a dent** (`Bend._dent`). Upright and wider. A blow
   pushes the nodes within 0.55 m of it in, away from the blow: 0.06 m a
   point under the fist, less farther off; its foot stays where it is.
   The rest stays flat, dents add up, and a blow from the other side
   pushes back. A dent is not a body: each node is drawn pushed in, in
   the sheet, wherever the sheet goes (`ShardMesh.set_offset`).
4. **In one place.** What a piece has taken is what it has taken where
   it has taken the most: its deepest kink, its deepest dent. Blows
   elsewhere start another mark; they do not bring it down sooner.
5. **Lying down** (`Structure._drop`). Marked as deep as it goes, a
   sheet becomes one loose body, dents and all, and goes over away from
   the blows. A post becomes its limbs, each a body, joined at its
   kinks.
6. **Folds** (`Rubble.join`). Where two bodies of one piece of metal are
   joined, the piece folds: a hinge held by a motor told to stay still,
   with only so much force (`Matter.FOLD`: 450 000 N.m for each metre the
   fold is long and each metre squared the piece is thick, at real
   gravity). Under less it holds; under more it gives, slowly, and stays
   as it ends up. So a post that lies down keeps its shape, and one that
   gives under a deck folds under it instead of staying up. Bodies
   joined to one another are frozen, and move again, together.
7. **A plate sags** (`Structure._drop_plate`). A piece that lies flat (a
   deck) takes nothing from a blow. It is made of triangles, two to a
   square about 1.8 m across, cut one way and the other in turn so that
   it can fold along its diagonals too. As soon as one of the pieces
   under it goes, they become bodies joined by folds: the plate sags
   where nothing holds it, and folds as it comes down. It stays tied to
   the pieces under it that still stand (`Rubble.tie`, with 0.15 m of
   play to fold over their edge): it hangs from them until they go too.
8. **It never breaks**, however hard it lands (`Structure.shatter`
   leaves it alone).

### A house: a frame that carries, planks that clad

Nothing new breaks here: the house is wood, with panes of glass, and
each answers as it does elsewhere. What is new is what rests on what
(`Main._lay_house`), and three things the engine learnt for it.

1. **A frame.** Four corner posts 0.14 m thick and 1.5 m high. On each
   pair along the ridge, a plate (a beam 0.1 m high). In the middle of
   each gable a taller post, and on those two the ridge beam. On each
   slope four rafters, which lean 30 degrees from the plate up to the
   ridge and go 0.25 m past the wall. It is drawn darker than the rest
   (`Structure.add_piece`, `shade`).
2. **A roof on the rafters.** Four boards on each slope, laid along the
   ridge, 3.4 m long: they go 0.2 m past each gable. A tilted piece can
   carry another: where two pieces are over one another, the one rests
   on the other if its underside passes at the height of the other's
   top (`Structure.build`, `_face_at`). That is all over, for a board on
   a rafter that leans the same way, and along a line for a rafter on a
   plate.
3. **Planks that carry nothing.** The walls are planks that stand
   between the posts, as in the palisade. They stop 0.04 m short of what
   is over them, so nothing rests on them: the house stands on its
   frame. The planks of the gables rise with the roof, behind the end
   rafters.
4. **Windows, a door, a porch.** A window is a pane of glass on two
   low planks; glass that nothing holds any more bursts where it is
   (`Structure._settle`), it does not come down in one. The door is a
   panel of darker wood, in the wall that faces the start. The porch is
   a lean-to over it: four posts, two beams, three boards that lean from
   one beam to the other.
5. **What comes down.** A board that is struck keeps a hole and stays on
   its rafters. A rafter that is cut loses what was above the cut, and
   the boards stay on the three others. A plate that is cut, or loses a
   post, comes down with its four rafters and the four boards of that
   slope. The ridge that loses a post comes down with the whole roof.
   The walls stay up: they are cut plank by plank.
6. **What the brute does to it.** At the middle of a gable, the first
   blow that lands cuts the post under the ridge (the leap, 1.9 m up,
   from a step and a bit away): the roof is down. At a long wall the
   straights knock holes in the edge of the roof and cut planks 1.4 m
   up, a pane bursts; when one of them takes the underside of the plate
   (1.5 m up), that slope comes down: at the fourth to the ninth blow,
   by where it stands.
7. **Its size.** Walls to the brute's shoulders (1.5 m), the top of the
   roof 2.4 m up; the brute is 1.8 m tall. With walls 1.35 m high the
   straights met the edge of the roof and the plate before the wall.
   The porch is lower (1.0 to 1.4 m): from in front of it only the leap
   lands on it; from beside it the straights take its boards.

### A building that stands turned

The streets of the city will not be straight (docs/CONCEPT.md), so a
building stands turned any way about the vertical. It is still laid out
straight. Its pieces are added in a frame (`Structure.frame`): where the
building stands, and how it is turned. `add_piece` takes the place of a
piece in that frame; `place` is where that puts it in the world.

1. **What rests on what is worked out in the frame**, where the pieces
   of a building are straight: the top and the underside of each piece
   and of each block, as rectangles (`_face`, `_foot`, `_head`); where
   they meet (`_meeting`); whether the middle of what is left is over
   what holds it (`_held`); which triangle of a plate is over a pier
   (`_tile_over`). It is the same arithmetic on the same numbers however
   the building is turned, so a building turned holds and comes down as
   it does straight.
2. **A blow comes in the world and is taken there**: which piece, where
   on it, which way its blocks go. Bodies, blocks, loose pieces, the
   dent of a sheet (along its own normal) and the kink of a post were in
   the world already.
3. **Pieces rest on one another within one frame only**
   (`Structure.build`). Two buildings do not carry one another: each
   stands on the ground.
4. **On the bench the house stands 30 degrees askew**
   (`Main.HOUSE_TURN`, `Main.house_frame`), its door still towards the
   start. `Main.house_turn` turns it another way the next time the bench
   is put back: the tests lay it five ways.
5. **A plate hangs from its piers wherever it stands.** A deck that
   comes loose is tied to each pier by the triangle that is over it. It
   was found by asking of each triangle whether the middle of the pier
   was inside it; the piers of the bench stand right under a fold,
   between two triangles, where the answer hung on the last digit of
   where the deck stood. Laid out 40 m from the middle of the bench, the
   same deck was tied to none of its piers. It is tied by the nearest
   triangle now.
6. **The shape of a block is laid out straight too.** Its collision
   corners are kept as its piece is laid out, and the shape is turned as
   the piece is where it is put in a body (`_shape_of`, `_free`, `_fall`,
   `_refresh`). Kept as they stood in the world, the corners of a flat
   face of a turned block were flat to the last digit but one, and such
   a block did not come to rest on that face: it rocked on the ground
   for good, 4 to 5 cm into it (in 6 of 12 turned walls that were holed;
   in none of 16 since, see docs/PERFORMANCE.md). A block of a piece that
   is not turned has the shape it had.

### An office building: columns that carry, glass that does not

`Main._lay_office` and `_lay_storey`: 71 pieces, concrete and glass, on
the brute's left as it starts, its front towards the start, askew.

1. **What carries what, from the ground up.** Six columns 0.25 m thick,
   three along the front and three along the back, carry the first slab.
   On each slab stands a storey: a low wall all round; on it, piers,
   which carry the next slab; between the piers, a pane in each window.
   The last slab is the roof. Panes carry nothing: those of the ground
   floor stand between the columns, on the ground; all of them stop 4 cm
   short of the slab over them, so that nothing rests on them.
2. **The ground floor is taller than a storey** (1.55 m under its slab,
   0.8 m for a storey): the brute's straights land 1.4 m up. With three
   storeys of the same height they would have passed over the ground
   floor, and the columns, the only things that bring the building down,
   would have been out of reach. The fists reach the panes and the
   columns of the ground floor, the edge of the first slab from below,
   and the low wall of the first storey (the leap lands 1.9 m up). What
   is higher comes down with the rest or not at all.
3. **A column gives at the third straight that lands on it**, the
   fourth blow (the leap that ends a combination lands over it, on the
   low wall of the first storey): its top is knocked out and a stump
   stands, 0.8 or 1.2 m high. The slab holds as long as its middle
   is over the columns that are left (`_held`): on five, it does. With
   the three of a long side cut it comes down, in one; and everything
   over it is no longer carried and comes down at once (`_let_go`: two
   slabs, eight low walls, twenty-eight piers; twenty panes burst). It
   goes over towards the side that was cut, on the columns that still
   stand, and breaks into its blocks as it lands.
4. **Glass holds nothing up** (`Rubble._moved`, `Structure.fragile`). A
   loose body of more than 40 kg that comes to rest on top of a pane
   makes it give, however gently it came. Until now only a hard landing
   counted. The slab, its columns cut, went over 4 cm onto the panes of
   the ground floor: too gently to count, and the whole building stood
   on glass, its roof where it was.
5. **A slab that tips has come down by its far edge** (`Rubble._land`).
   What comes down in one breaks when something stops it once it has
   come down 0.3 m. That was measured at its middle. The slab landed on
   the stumps of its columns (1.16 m high, under a slab that was at
   1.55 m), its middle not 0.3 m lower: it stayed whole, leaning, the
   two storeys still on it and the roof 0.12 m lower than it was. For a
   piece that lies flat, how far its far edge has come down as it tipped
   is now counted too.
6. **A blow at its foot does not look at all of it** (`_let_go`,
   `_shed`). When a piece loses something, what rests on it is looked at
   again. So was everything over that, all the way up, whether it had
   lost anything or not: one blow that knocked blocks out of the first
   slab, or cut a column, looked at the seventy pieces of the building,
   in script, 16 to 22 ms for that step (docs/PERFORMANCE.md). Now it
   goes on up only through what loses something in its turn: what loses
   nothing still holds all it held. What comes of the same blows is the
   same, block for block.

Not there: what falls does nothing to the brute but push it (a deck that
comes down round a brute that cannot get out stays on its head); blocks
that lie in one come apart under blows only once they have taken the
strength of their piece in all; a hole is the blocks round the fist, two
to five of them, not a fist's exact shape; what holds over a hole goes
by which block is over which, not by weight, so how many holes it takes
to open a wall to the top depends on how the wall was cut (two or three
side by side); a slab that tips onto
what is left under it breaks there only if that stops it short (by 0.8 m
a second in a step), else it stays whole, leaning; glass gives under
what comes to rest on top of it, not under what leans against it nor
under what weighs 40 kg or less; with the front of the office building
cut, a strip of it can stay up on the columns of the back, as high as
the floor of its second storey; that building has no door, no stairs and
nothing inside; metal that lies there no
longer takes a mark; a sheet that stands dented is
still a flat wall to the brute; a plate takes nothing from a blow;
wood only snaps across its grain, never splits along it, and a long
piece struck where it lies comes apart into all its lengths at once,
not only where it is struck; a plank that is snapped keeps its foot
standing, however short; the brute's body goes through what lies loose,
small wood included, as it lunges;
pieces are boxes that stand upright or lie flat; only one that lies flat
can be tilted, about one level axis; what holds a tilted piece goes by
where it is over what it rests on, seen from above, not by how it leans
or where it would slide (the stub of a cut rafter balances on its
plate); a building is turned about the vertical only (nothing stands on
a slope), and its pieces do not rest on those of another; the house has
no floor, its door does not open, and its gables show small steps under
the end rafters (a plank's top is level).

## The bench

A ground 400 m across, at height 0, in one colour with a line every metre
and a heavier one every five (`shaders/ground.gdshader`, computed per
pixel: no picture). On a bare ground the lines are what shows how fast
and how far the brute goes.

The sun casts no shadow: on the phone the version before was measured on,
its shadows were what cost the most. The brute has a round shadow
(`BlobShadow`) that lies on the ground under it, found by a ray each
physics step, and gets smaller and fainter as the brute goes up.

On it, a few steps in front of the brute, the same three things three
times, and panes of glass behind it.
In concrete, on its right: a column 2.6 m high on its own; a wall in one
piece (3.6 m wide, 2.4 high, 0.35 thick: wide enough to keep a hole); a
slab 3.6 m across on four columns 2.2 m high. In metal, on its left: a post 0.2 m thick; a
fence of three sheets 0.08 m thick; a deck 0.12 m thick on four posts.
In wood, straight ahead and farther off: a post 0.2 m thick (10 m
away); a palisade of ten planks that stand side by side, each a piece
(0.3 m wide, 2.4 high, 0.06 thick: 13 m away); a floor of eight boards
laid across two beams on four posts 2 m high (19 m away).
In glass, behind the brute as it starts (8 m away: the other sides are
taken): three panes side by side, 1.2 m wide, 2.4 high, 0.04 thick.
And a house on its right as it starts and level with it (its porch 5 m
away): 2.4 m across, 3 m along its ridge, 2.4 m high, of 70 pieces (see
"A house" above). It stands 30 degrees askew (see "A building that
stands turned"). And an office building on its left, opposite the
house (its front 7 m away): 3.6 m across, 2.4 m deep, 3.6 m high, of 71
pieces (see "An office building" above). Its front faces the start, 20
degrees off the lines of the ground. In all 185 pieces, drawn as 1077
parts.
"Reconstruire" puts them back and the brute where it started, without
loading anything again (`Main.rebuild`).

## The character

The mannequin and its clips are the free part of Quaternius's Universal
Animation Library (CC0, see `assets/mannequin/SOURCE.md`): one rigged
figure, 46 clips, of which 7 are played. The blows are not from that
library: see below. `scripts/player/character.gd` builds the tree that
blends all of them; `scripts/player/player.gd` moves the capsule and
tells the character how fast it goes, whether it is in the air, and when
it jumps, lands or strikes.

- **Legs that keep pace.** Each clip has one ground speed at which its feet
  do not slide: 1.05 m/s for the walk, 5.2 for the jog, 7.8 for the sprint
  (measured on the clips: the speed of the ankle while the foot is flat on
  the ground). The run and sprint speeds of the game are those. In
  between, two clips are mixed: both are stretched to one common cycle, so
  the same foot is forward in both, and that cycle is the one at which the
  mixed stride covers the ground actually covered. Below a walk, the walk
  is slowed down, then its steps shortened into standing.
- **The air.** A jump leaves at once (the clip's crouch is skipped), runs
  into the pose held in the air, and ends in a landing only when you come
  down hard or on the spot: running, the legs run on.
- **Blows made for games.** The three blows come from Quaternius's two
  Universal Animation Libraries (CC0, the free versions; see
  `assets/fight/SOURCE.md`): animations drawn for games. The first has
  two punches made as punches, a straight left and a straight right
  thrown standing from a guard, the fist 1.4 m up and the body going
  nowhere; the second, a leap that ends fist first on the ground (the
  last stroke of a sword combination, thrown without the sword). Their
  skeletons are the mannequin's own, so `tools/moves/build.py` takes the
  clips over as they are and measures them. What is measured on each is
  stored with it: when the fist gets there (the blow counts then at the
  latest), when the next move may start, how far and how high it
  reaches, and whether it is thrown with the left hand (the fist that is
  followed, and the hand left out of what is held back from what
  stands, go by it).
  The owner chose these on 19 November, having tried them beside the
  four the brute had (a lunging hook and three sword strokes, which all
  dived: fists 0.7 to 0.85 m up) and an uppercut from motion capture.
- **Three blows, one button.** The owner decided on 19 November to keep
  only the combination. The kick, which was what a real person did (CMU
  motion capture database), is out: its animation was wrong. A lower,
  quicker kick from the same database (branch `refonte/coup-de-pied`)
  and a blow of both fists brought down, made by the tool out of a throw
  (branch `refonte/marteau`), were tried the same day and set aside. The
  tool still reads captures (`tools/moves/bvh.py`, `retarget.py`): its
  list of them is empty.
- **The combination.** A straight left, a straight right, a leap that
  comes down fist first, then round again. The next blow starts when the
  one before lets it (`next` in its clip).
- **Steps that are real.** The straights stay where they are; the leap
  steps (1.4 m). The steps are on the skeleton's
  root bone; the game moves the body by them (root motion), so a planted
  foot stays planted. A blow is thrown where the stick pushes, or where
  the character faces.
- **The clock of a move.** A fist goes more than a metre between two
  frames of these clips, so the blow has to count on the very step whose
  pose shows it there. A clip starts at the end of the step that takes
  the move up, whoever asked for it (a key between two steps, a button or
  the combination during one): `Character` counts from there, and the
  clips say their blow lands on one of their own frames. `struck` is sent
  before the pose of that step is set; `reached`, which says where the
  limb is, once it is.
- **Where a blow lands.** Where its fist first touches something, not
  where the move ends. From 0.1 s before a clip has its blow land, and
  until it does, `Character` says at each step where the arm that
  strikes is drawn (`reached`: shoulder, elbow, knuckles), once the pose
  of the step is set. `Player` moves a
  ball as wide as a fist (0.1 m in radius) from where the knuckles were
  a step before to where they are, once they are in front of the body:
  the first thing it touches, standing or loose, takes the blow, at that
  point and in that step (`Player._touched`). If the fist touched
  nothing, what the forearm, then the upper arm, runs through does. And
  if nothing has by the pose in which the clip has the blow land, what
  stands between the body and the fist (a ball 0.2 m in radius, from the
  body's axis at the height of the shoulder): the brute's moves lunge so
  far that its chest can be through a thin column while its fist is past
  it. Nothing at all: the blow is said where the fist ended, on nothing,
  and what a fist touches there (0.3 m round) takes it. A blow is thrown
  along the way the brute faces, wherever it lands.
  What this does: a step from a wall, the two straights go in 1.4 m up,
  straight ahead, and the fist of the leap 1.9 m up, over the brute's
  head: the fists land high. Nothing aims at what is below the
  shoulder. Only the leap comes down: its clip has its fist land 0.85 m
  up, so once the straights meet nothing it lands on what is left and
  lowers it. Measured on the bench: the planks of the palisade are low
  enough to walk over after a dozen blows; the wall keeps a sill 0.8 m
  high, which the brute clears with a jump, and it takes 65 blows, at
  three spots side by side, before it walks through.
  Before, a blow was a thin line from the body's axis straight ahead to
  where the fist ends in the open, at that height: 0.3 m to one side of
  a column 0.4 m wide, every blow missed it.
- **The body stays out of what stands.** The moves lunge well ahead of
  where the brute stands, which is all the physics knows of it (a
  capsule 0.35 m in radius): in the leap its left hand is 0.8 m ahead
  and its head 0.5 m (in the hook it had before, its head 0.9 m: up
  against a wall it dived into it to the shoulders). At each step of a strike, once the pose is set
  (`Character.posed`) and before the fist is looked at, `Player._on_posed`
  takes the parts of the body other than the limb that strikes
  (`Character.bulk`: head, chest, shoulders, left hand, knees, toes, each
  as wide as it is) and moves each, as a ball, straight ahead from
  beside the brute to where it is drawn. The farthest any of them would
  go into a piece that stands is how far the brute is moved back, there
  and then (`move_and_collide`: not into what is behind it). So the
  brute backs off as it lunges, up to 0.7 m, and only the fist and the
  arm go in. It stays where that leaves it. Not looked at: what lies
  loose (a blow sends it off), and anything while it is not striking.
- **Stepping up.** Stopped by something no higher than 0.6 m, with room
  above and something flat enough on top, the brute steps onto it: a
  short stride first, then one of 0.35 m if all there is under the foot
  after the short one is an edge: the foot of a wall that was knocked
  open is uneven on top (`Player._climb`). The view and the body follow
  over a moment, so that they do not jump.

Not there: strafing and walking backwards (the free clips only go
forward, so the character always turns to where it goes), feet placed on
uneven ground.

## The camera

Behind the left shoulder, turning about the head. A ray from the head to
the shoulder, then one back from there, find what stands in the way
(the world and what stands; what lies loose is not in its way): the
camera stays in front of it, going in at once and easing back out. With less than 1.4 m behind the shoulder it goes behind
the head instead; closer than 0.7 m it would only see the character's
back, which is then not drawn.
