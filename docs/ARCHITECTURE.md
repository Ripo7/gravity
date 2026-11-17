# Architecture

How the code is laid out, who owns what, and how the two systems that
matter (what breaks, what moves) work. Numbers are in
[PERFORMANCE.md](PERFORMANCE.md); where the assets come from is in
[CREDITS.md](../CREDITS.md).

## Layout

| Where | What |
| --- | --- |
| `scripts/main.gd` | builds the scene: sky, ground, the level (city or house), the two brutes, HUD |
| `scripts/core/` | launch options, input map, quality tiers, the physics clock, scripted runs (`director.gd`) |
| `scripts/destruction/` | what stands and how it breaks: `Fracture`, `Structure`, `Support`, `Pieces`, `ShardMesh` |
| `scripts/game/` | the levels (`City`, `House`), what the brutes have in common (`Fighter`), the other brute (`Brute`) |
| `scripts/player/` | `Player` (controls, camera) and `Character` (the animated body, shared by both brutes) |
| `scripts/fx/`, `scripts/ui/` | dust and chips; HUD and touch controls |
| `shaders/` | the one shader that draws every shard |
| `assets/` | the mannequin and the fighting moves (made by `tools/moves`) |
| `tools/` | CI and build scripts, the perf gate, the web probe, the asset tools |
| `tests/` | headless tests, one file per subject |

Everything is built in code: there are two scenes, `scenes/main.tscn` (one
node with `main.gd`) and the test runner's.

## Who owns what

- **`Main`** creates everything and hands each part what it needs
  (`player.pieces`, `fighter.structure`). Nothing looks its neighbours up
  by path.
- **`Structure`** owns the shards, their bonds and the loose `Pieces`. The
  rest of the game breaks things through four calls: `shards_near`,
  `strike`, `blow`, `shatter`. It says what came off with one signal
  (`released`), which `Main` turns into dust and chips.
- **`Character`** is a body you see and nothing else: it is told what
  happens (`move`, `jump`, `punch`, `hit`, `blown`...) and turns it into a
  pose. It says when a strike starts and when it gets there (`swung`,
  `struck`); it never decides who is hit.
- **`Fighter`** is the rule book of the fight, one per brute: what a strike
  does to the other brute and to the walls, what being hit and being thrown
  mean. `Player` and `Brute` are two ways of steering a body that has one:
  a person's thumbs, or a few lines that walk up and attack.
- Signals go up, calls go down; a child never calls its parent.

## One physics step

`Player` and `Brute` move their capsules, then each `Character` advances
its move and its animation tree (the trees are stepped with the physics, so
the steps of a blow reach the capsule at the same pace), then
`Structure` spreads what it has to do (what holds, what falls) over the
step. Collision layers: 1 world, 2 structure, 3 debris, 4 player, 5 actor
(the other brute); a body off its feet keeps only the ground. Loose
pieces are stopped by the brutes as by a wall: a piece that only went
through one would carry it along.

## Conventions

- GDScript is typed everywhere; the warnings a reviewer would send back
  (untyped, unused, shadowed, unreachable) are errors in `project.godot`,
  so a script with one does not load and the tests fail.
- `gdlint` and `gdformat` decide the style; class order is constants,
  variables, then functions.
- Every tuning number is a named constant with a comment that says what
  it means and its unit.
- Comments say why. A claim about speed or cost comes with a measurement.
- Scripted, seeded runs (`--mode=play`, `--mode=showcase`) are how clips
  and numbers are made, so both can be made again.

## The character and the fight

The mannequin and its clips are the free part of Quaternius's Universal
Animation Library (CC0, see `assets/mannequin/SOURCE.md`): one rigged
figure, 46 clips, of which 9 are played. The fight is not from that
library: see below.
`scripts/player/character.gd` builds the tree that blends all of them;
`scripts/player/player.gd` moves the capsule and tells the character how
fast it goes, whether it is in the air, and when it jumps, lands,
strikes, kicks or guards. The other brute (`scripts/game/brute.gd`) is the
same character in other colours; what the two have in common (what a
blow does, being thrown) is in `scripts/game/fighter.gd`.

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
- **Blows made for games.** The four blows, being thrown and getting up
  come from Quaternius's Universal Animation Library 2 (CC0, the free
  version; see `assets/fight/SOURCE.md`): animations drawn for games,
  with big poses and blows that land within a third of a second. Its
  skeleton is the mannequin's own under other names, so
  `tools/moves/build.py` takes the clips over as they are, joins each
  stroke to its recovery and measures it. One was made as a punch (the
  hook); the others are sword strokes thrown without the sword. What is
  measured on each is stored with it: when the fist gets there (the blow
  counts then), when the next move may start, how far and how high it
  reaches, and which way it is going.
- **What is still motion capture.** The kick is what a real person did
  (CMU motion capture database, free to use): the free library has none.
  The tool puts it on the mannequin's skeleton
  (every bone takes the turn its joint made since the T pose; the hips go
  where the hip joints were, scaled by the length of the legs) and
  retimes it (a slow wind-up, the last 0.12 s in two thirds of
  their time, the pose all but held for an instant after).
- **The combination.** A lunging hook, a swing up from the right, one
  back across from the left, a leap that comes down fist first, then
  round again. The two swings were made to follow one another; the next
  blow starts where a stroke ends, and its recovery only plays when
  nothing follows.
- **Steps that are real.** The blows step, some a long way (the swing up
  dashes 0.8 m in, the leap 1 m). The steps are on the skeleton's root
  bone; the game moves the body by them (root motion), so a planted foot
  stays planted. A strike also goes for the opponent in front: the
  character turns to it, and its steps are fitted to it until the blow
  lands, carried farther if the fist would stop short (that part slides)
  and held back if they would take it past, so that the fist ends on the
  other: 0.22 to 0.24 m from its axis for all four. A blow under way is
  not cut short by stepping off a heap of rubble, and its steps go up
  onto rubble like any others.
- **The clock of a move.** A fist goes more than a metre between two
  frames of these clips, so the blow has to count on the very step whose
  pose shows it there. A clip starts at the end of the step that takes
  the move up, whoever asked for it (a key between two steps, a button or
  the combination during one): `Character` counts from there, and the
  clips say their blow lands on one of their own frames.
- **Blows.** When a fist or a foot gets there, the other brute takes it
  if it is in front and within reach. The first three make it flinch,
  flash white, lean and slide the way the fist goes (back for the hook,
  to the left for the swing up, to the right for the one back across:
  5 m/s, about 0.6 m). The leap, which ends the combination, and the kick
  throw it: 12 m/s along the ground, 4 up. After a blow the body stands
  again: there is no stance in between.
- **The guard** (`Player.guard`, `Character.guard`, `Fighter.blocks`).
  Held, it is one pose, both fists up in front of the face (the pose the
  hook's recovery ends in), feet still, turned to who the player is
  locked on. A blow that comes from within 1.2 rad of where the body
  faces stops on it, whatever the blow: no flinch, no throw, a push of
  1 m/s for each point of power, a short hold and a small jolt. From
  behind it does nothing. A strike can be thrown from it; it comes back
  after the strike if it is still held. The other brute never guards.
- **The instant a blow lands** (`Fighter.STOP`, `Character.hold`). Both
  brutes are held still, 0.07 s for a blow and 0.12 s for one that
  throws: the pose, the move under way and the body, on the frame in
  which the fist is on the other (who trembles, white). What is pressed
  meanwhile waits. `Fighter.jolted` says how hard it was; the player's
  camera shakes by it (about 2.9 degrees when it is thrown, 0.7 for a
  blow it lands, dying out in a third of a second). A blow at nothing does
  neither.
- **Locking on** (`Player.lock`; the fight starts locked). The nearest
  other brute is marked with a ring and a strike always goes to it. The
  camera stays on it, looking 0.6 rad to the right of the line to it: the
  two are seen side by side, the character on the right, instead of one
  behind the other (0.17 rad apart on screen at arm's length, 0.04 with
  the camera straight behind). If the blow would not land from
  where the character stands (the other is farther than its reach and a
  step of 0.5 m, or something stands between them at chest height), the
  character sprints at it first and strikes when it would: no blow is
  thrown at nothing. Held up 0.15 s on the way by what stands, it goes
  through: a hole its size (`Fighter.breach`, the one the other brute
  makes). It gives up after 4 s; taking up the guard or jumping calls the
  run off.
- **Thrown.** A brute off its feet goes over backwards and flies, back
  first. Nothing that stands stops it: every step of its flight, the
  shards within 0.95 m of its middle are knocked out (the nearest in
  crumbs), each one taking a little of its speed, so it goes through a
  wall, across a room and out through the next. It tumbles over
  backwards, lands on its back, slides, lies 0.7 s and gets up (1.2 s).
- **Fists break what stands.** A strike that reaches a wall or a pillar
  knocks out what is within 0.7 m of where the fist meets it (1 m for the
  leap or a kick), and sends off the loose pieces that lie there. A blow
  that lunges reaches past the body: the hole is made at the first
  standing thing on the fist's way.
- **The other brute** has no plan: it walks straight at you, stops at
  arm's length, and after a wait of 0.5 to 1.3 s kicks (3 times in 10) or
  throws one to four blows of the combination. It steps onto rubble;
  stopped by a wall for a third of a second, it kicks it in and goes
  through. From behind the house it reaches you in front of it in 6 to
  9 s, 34 to 37 shards knocked out on the way.

Not there: strafing and walking backwards (the free clips only go
forward, so the character always turns to where it goes), feet placed on
uneven ground. For the fight: no health and no end (it goes on until the
house is gone), moving while guarding, a guard that gives way under
enough blows, the brutes being any bigger than people. Who takes a blow
leans in one piece, about its feet. Locked on, the camera cannot be
turned, there is no circling around the other, and the stick still
pushes the character where the camera looks, which is no longer straight
at the other. A thrown body passes through loose rubble; a brute that
stands is still pushed a little by a piece that lands against it.

What the free version of the library leaves to be desired: three of the
four blows are sword strokes, so the arm swings as if it held one; the
hook and the leap were not made to follow the two swings, a blend joins
them; there is no kick in it. The paid version has the combination, the
knee and the uppercut that were made bare-handed, a ground pound,
hits taken in the air and walking in eight directions.


## How the destruction works

1. **Cut once, at load** (`scripts/destruction/fracture.gd`). Every box of
   the house (wall, slab, pillar) is cut into convex shards about 0.6 m
   across, of mixed sizes, by a Voronoi diagram. Across a thin box distances
   count for more, so the cuts lean instead of going square through a wall,
   and a pillar also splits along its length. Neighbours share exactly the
   same corners, so an intact wall has no gaps. The house is 1516 shards and
   is cut in about 0.25 s (0.6 s in a browser); rebuilding it reuses the
   cut.
   A city is 800 to 2000 shards (cut in 0.2 to 0.4 s headless): what is
   low or small is cut plain (a house in four to six shards, a car, a roof or a
   tree's crown in one), offices and towers at 0.75 m. It is light (300
   kg/m3, `Structure.density`): a toy city is hollow.
2. **Bonds** (`structure.gd`). Shards that touch are bonded, with the area
   they share; so are the shards of two boxes that touch. Shards on the
   ground are anchors.
3. **What holds** (`support.gd`). After any damage, a look at the bonds
   finds what is still tied to the ground (the rest comes off, in rigid
   chunks of 32 shards at most, 45 while a lot is already moving) and how
   loaded each bond is: weight hangs on the bonds below, and overhangs pull
   harder the farther they stick out. Overloaded bonds break, so a balcony
   without its pillars comes down by itself, a bit at a time. The look is
   spread over several physics steps (about 1 ms each), and so is a big
   fall (28 shards per step).
4. **Pieces** (`pieces.gd`). What comes off is a rigid body made of its
   shards' convex shapes. The energy a piece loses in hits (all at once in
   a hard landing, or added up over a gentle one) crushes that much of it
   around the contact (the nearest half into crumbs, the rest into single
   shards) and cracks the rest, and it splits along the broken bonds; half
   goes into the building if that is what it hit. So a big slab does not
   survive coming down. Pieces that lie still are frozen (static) and wake
   when something near them moves.
5. **Crumbs.** A shard that is hit hard (where a blow lands, a
   lone shard that lands or is thrown against something at 6 m/s or more,
   the point where a falling piece strikes) is cut once more, there and
   then, into 2 to 6 crumbs that fill it exactly. Each crumb is one more
   body, so they are rationed: 3 shards per step, none while more than 260
   pieces are moving, and no more than a fixed number in all (250 on a
   phone, 450 in a browser, 800 on a desktop), with fewer and fewer made as
   that fills up.
6. **Two draw calls** (`shard_mesh.gd`, `shaders/shards.gdshader`). All the
   shards are one mesh; a small texture tells the vertex shader which body
   each shard follows and where that body is. The checker is laid from the
   place a shard had in the house, so it stays on the pieces. Faces made by
   a cut are only drawn once the two shards are apart; their middle is
   pushed in or out and each facet is lit on its own, like broken stone.
   The crumbs are a second, small mesh drawn the same way, made again when
   some are added.
7. **Collisions of what stands.** A whole box collides as a few plain
   blocks; the first shard to leave a block turns it into one static shape
   per shard, so the holes are real. A shard knocked out fast goes
   through what still stands for 5 steps: with leaning cuts it would often
   be wedged in its own hole.

Scripted runs break the house without a fight: `Main.blow` lands a
brute's blow on the first standing thing along a ray (the shards centred
within 0.7 m are knocked out, the nearest half in crumbs, and those up to
1.05 m crack). The showcase and the web probe use it, one every 0.3 s.

Quality tiers (`scripts/core/quality.gd`: phone, browser, desktop) change
the dust, the decorative bits and how many crumbs there can be. The house,
its shards and what holds are the same everywhere.

## The city: giants in a toy town

- **Made up from a number** (`City.new(number)`). The same number gives
  the same city. Streets 5.5 to 9.5 m apart cut the ground into three or
  four rows of three or four blocks; a block that is not on the edge is
  the square (its middle is the world's). Each other block is a district
  (downtown, houses, park; downtown six times in ten next to the square,
  two in ten elsewhere, and twice at least) and is cut in two again and
  again into lots 2 to 4 m across. A lot gets a tower (one or two per
  downtown block, two to five in a city), an office, a row or two of
  houses, or trees. Cars go along every avenue, and two cities in three
  have a railway down one of them. The city is first a list of boxes
  (`_boxes`), whose cost in shards is told without cutting anything
  (`weight()`); above `City.MOST` (1900) it is planned again, with the
  same streets and less on the lots. `Main` picks the number: set by a
  test, `--city=`, else `--seed=`, else at random; the plan also tells
  where things are (`towers`, `offices`, `houses`, `cars`, `blocks`), for
  the showcase tour and the tests.

- **Wading** (`Fighter.wade`, `trample`). After each step a brute takes,
  what stands in front of its knees, no higher than `Fighter.WADE` (1.2
  m) above its feet, may give way: at any pace if it weighs `LIGHT` (70
  kg) or less in all (a car, a tree, a stilt of the railway), and
  otherwise (a house) only if the brute means to go at `RAM` (6.5 m/s) or
  more, a sprint or a charge, which then loses `BRAKED` (0.4) of its
  speed. At a walk or a jog a house is a wall. What a brute lands on that
  is that low is shattered. Higher things (offices, towers) stop it.
- **Solid things stand up to blows** (`Fighter.smash(..., tough)`,
  `SOLID`, `Structure.thick`, `wear`). How solid a box is, is how thick it
  is the way it is thinnest, in units of 0.7 m, from 1 to 3: a wall, a
  slab or a house is 1 and gives as before; an office or a tower is 2 or
  3. A blow or a charge makes a hole that many times smaller in it, and
  each shard in the hole gives only at that many blows; a blow that
  breaks nothing throws chips and dust off the face (the `released`
  signal). In a scripted run a tower hit at its foot comes down during
  the third four-blow combo (the first, before). A brute that is thrown,
  and the scripted blows of the showcase and the tests (`Main.blow`), are
  not held back.
- **A blow that is stood up to shows** (`ShardMesh.set_worn`, the scars in
  `shaders/shards.gdshader`). The texture that tells each shard's body
  carries a second number: the share the shard has taken of the blows it
  can take (`Structure.wear` sets it). Where it is above 0, the shader
  cracks the face of the shard into chips (points scattered 5.5 to the
  metre, the nearest two looked for among nine squares) and takes off the
  chips whose own number is under a threshold that rises with the share:
  what the wall is made of shows there, bricks or concrete. So the second
  blow at the same place widens what the first began, and the third goes
  through. It fades towards the edge of the shard, whose neighbours took
  nothing: for that, a face of the box is a fan round its middle, which
  is marked (one vertex more a face). Only the pixels of a worn shard pay
  for it. A shard that comes off keeps its scars as a piece.
- **Litter** (`Pieces.LITTER`, `Structure.LAYER_LITTER`). A loose piece
  of 500 kg or less is on a layer of its own that the brutes neither
  collide with nor are pushed by; heavier pieces still block and can be
  climbed. (The rubble of the house, at 2400 kg/m3, is mostly litter too.)
- **Columns** (`Structure.SLENDER`, `FOOT`, `TOPPLE`). A box more than
  twice as high as it is wide is told in storeys one grain high. When less
  than half of a storey still stands, everything above it, and what stands
  on it, comes off together, turning at 2 rad/s about the edge that still
  holds: the tower tips over away from the blows instead of settling into
  its own hole, and breaks up where it lands. The load rule (`Support`)
  could not do this on its own: as built, a tower's foot is far below what
  breaks a bond, and making the city brittle enough to fall that way made
  the railway fall down by itself.
- **Showcase and tests.** The tour comes from the level (`city.tour()`,
  `House.tour`); every older test runs on the house (`main.level =
  "house"`), the city has its own (`tests/test_city.gd`).
- **Walls** (`ShardMesh.Look`, `shaders/shards.gdshader`). A box is added
  with a look: the grid of the test ground, its paint alone, or a house,
  an office, a tower, roof tiles. For a wall, each vertex of a face of the
  box carries where it is among the bays and floors of that face (`BAY`,
  `FLOOR`: a whole number of each fits the wall, so no window is cut at a
  corner); the shader picks the tile (ground floor, a floor in between,
  top floor; one door to a house), paints it where its alpha says so with
  the box's colour, and uses its relief as a normal map, turned with the
  piece once it falls. Broken faces show bricks or concrete. The tiles are
  made by `tools/blender/facades.py` (Blender as a Python module, no
  interface: bmesh for the shapes, shader nodes for the passes, Cycles to
  bake) and loaded as two `Texture2DArray` of sixteen layers. It is still
  one draw call. The two pictures are stored lossy (their `.import`
  files): 0.23 MB in the web package instead of 1.04, which is 2.6 MB in
  all.
- **The camera, hemmed in** (`Player.TIGHT`). The camera sits behind the
  brute's shoulder. When there is less than 1.4 m of room behind the
  shoulder (the brute is in the hole it has punched in a tower: the wall
  is right beside it), it goes straight behind the head instead, the way
  the brute came in, if there is more room there; it used to be pulled
  right up to the head, the brute hidden and the wall filling the screen.
- **The camera and rubble** (`Player.in_the_way`). The camera stays in
  front of what stands, and of rubble that has come to rest and is big
  enough to hide the fight (`HIDES`, 0.35 m); pieces still moving and
  small bits are let through, so that it does not lurch at everything
  that flies past.
- **Keeping pace** (`Main.keep_pace`, `eased`). Told each frame how long
  the last one took; below 40 frames a second over two stretches of 3 s
  it turns the sun's shadows off for good and shows a round shadow under
  each brute, then, if still slow, draws at three quarters of the
  resolution. Not in scripted runs nor without a screen.
- **Relief without shadows** (once the sun's shadows have been given up,
  and with them too). Three things that cost next to nothing: the ground
  is drawn darker where something stands on it and a little around
  (`City.ground_shade`: the footprints of the boxes drawn into a 512 px
  picture, shrunk to 64 so that the edges fade; one look-up in
  `shaders/ground.gdshader`); a wall is darker over its lowest 45 cm; and
  what faces down or sideways gets less light than what faces the sky,
  which gives rubble its shape. The bricks and the concrete of broken
  faces are laid finer (5 tiles to the metre).
- **Models** (`ShardMesh.add_model`, `Look.CAR` and after). A box that is
  left in one piece (a car, the crown and the trunk of a tree, a coach of
  the train) can be drawn as a small model instead of its six faces: the
  model's triangles carry the shard's number like any other, so they move
  with its body and vanish with it, in the same draw call; its physics is
  still the box. A car is now one box, not two (106 shards fewer in city
  49), but its 80 triangles are more than a box's twelve: city 49 goes
  from 84 107 to 114 501 vertices, built in 0.45 s instead of 0.42.
- **The ground** (`shaders/ground.gdshader`, one material for the floor
  and for the slabs under the blocks). Nothing on it is a picture: the
  shader is told where the blocks are (`City.columns`, `City.rows`: four
  each way at most), the avenues between them (`City.avenues`) and what
  each block is, and works out for each pixel how far it is inside a
  block or from the middle of a street. From that: on the road, dashes
  down the middle, a line along the parked cars, bars across at each
  corner, a darker gutter; on a slab, a kerb, paving stones, then a lawn
  (houses, parks), plain paving (downtown) or the square's two stones and
  its ring; past the last blocks, fields in plots, with the avenues
  running on. A picture sharp enough for a line 4 cm wide over 50 m of
  city would be 4096 px across; this takes no memory and stays sharp
  under the camera. Lines are smoothed over the width of a pixel and
  what repeats (dashes, bars, joints) turns to its mean from far, so
  nothing flickers. The same look-up as before darkens it where things
  stand.

