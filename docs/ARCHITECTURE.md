# Architecture

How the code is laid out and who owns what. What the game is to be is in
[CONCEPT.md](CONCEPT.md); numbers are in [PERFORMANCE.md](PERFORMANCE.md);
where the assets come from is in [CREDITS.md](../CREDITS.md).

The game is at step 2 of its plan: a bench, one brute, and concrete to
break. The engine of the version before (boxes cut into shards bonded
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
| `scripts/destruction/` | what breaks: `Matter`, `Structure` (what stands), `Rubble` (what has come off), `Fracture` (the cut), `ShardMesh` (the picture) |
| `shaders/` | the ground's grid; the one shader that draws every block |
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
  happens (`move`, `jump`, `land`, `punch`, `kick`) and turns it into a
  pose. It says when a strike starts and when its fist or foot gets
  there (`swung`, `struck`), and what that blow is (`reach`, `height`,
  `power`). It never decides what the blow does.
- **`Player`** turns that into where the fist went and how hard
  (`blow`); **`Main`** hands it to the structure (`Structure.strike`).
  The brute knows nothing of what it breaks.
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
blow. One matter so far, concrete.

1. **Pieces** (`Structure.add_piece`). A piece is an upright box: a
   column, a slab, a panel of a wall. While it stands it is one static
   box for the physics.
2. **Strength belongs to the piece** (`Matter.strength`). So many points
   of blows for each metre the piece is thick the way it is thinnest:
   22.5 for concrete, so 9 for a column 0.4 m thick. A blow is 2 points,
   a heavy one (the last of the combination, the kick) 3: one whole
   combination brings that column down. Where the piece is hit and how
   it is cut change nothing to it.
3. **Cut once, when it is made** (`Fracture`, `Matter.grain`). Each piece
   is cut into a few irregular convex blocks, about 0.7 m across, bigger
   if that would make more than nine: 4 for the column, 6 for a panel, 9
   for the slab. The cut only says what the piece looks like cracked and
   what it breaks into.
4. **Cracks** (`Structure._crack`). A piece that has taken a blow shows
   its cut: each block is drawn a little smaller and askew, the gaps
   dark. From half its strength on, wider. The cracks are where it will
   break.
5. **Letting go** (`Structure.shatter`). A piece that has taken all it
   can breaks into its blocks, which become loose bodies. They start off
   as if the whole piece turned about its foot, away from the blow, and
   come apart as they go down: the piece goes over and ends as blocks
   lying on the ground. Left where they stood, blocks cut one on top of
   the other stayed there, a broken column still standing and still
   carrying. For their first 0.45 s the blocks also hardly rub on
   anything (`Rubble.FRESH`), so that those caught under a slab slide
   out from under it.
6. **What is no longer carried comes down** (`Structure._held`). A piece
   rests on the pieces right under it. When one of them goes, it holds
   if it stands on the ground or if its middle is still over what is
   left under it (the slab holds on three columns, not on two on the
   same side). Otherwise it comes down in one piece, a loose body with
   the shape of the piece, and breaks into its blocks when it is stopped
   as hard as by a drop of 0.3 m.
7. **Only a blow breaks.** From the brute: `Structure.strike` follows the
   fist from the body to where it ends; the first piece on its way takes
   the blow, and what lies loose near the end is sent off (not far: it
   is heavy). Or from something heavy that lands on a piece
   (`Rubble._land`): a point for each 900 kg.m/s it loses against it,
   and only on a face that looks up. What brushes past a wall on its way
   down does nothing to it. Walking, running and jumping break nothing:
   what stands is a wall to the brute.
8. **The rubble** (`Rubble`). Loose bodies are made straight on the
   physics server, no nodes. They fall at a share of real gravity
   (`fall`, 0.3 to begin with, set by the slider): slowly, which is what
   makes the brute a giant. Speeds told "as at real gravity" in the code
   go with the square root of that share, so the same things happen at
   any setting, only slower. A body that touches something and has been
   still for half a second is frozen (static): a heap costs nothing,
   stays put, and the brute steps onto it. It moves again when a piece
   near it breaks or when a blow lands by it.
9. **One draw call** (`ShardMesh`, `shaders/shards.gdshader`). Every
   block of every piece is in one mesh that never changes; a small
   texture says which body each block goes with (the world, its own, or
   that of a piece falling whole) and another where each body is. Faces
   made by the cut are only drawn once the two blocks are apart.

Not there: what falls does nothing to the brute (it is stopped by it as
by a wall); a blow on a piece that lies whole breaks it only once it has
taken its strength in all; pieces are upright boxes, turned about the
vertical at most.

## The bench

A ground 400 m across, at height 0, in one colour with a line every metre
and a heavier one every five (`shaders/ground.gdshader`, computed per
pixel: no picture). On a bare ground the lines are what shows how fast
and how far the brute goes.

The sun casts no shadow: on the phone the version before was measured on,
its shadows were what cost the most. The brute has a round shadow
(`BlobShadow`) that lies on the ground under it, found by a ray each
physics step, and gets smaller and fainter as the brute goes up.

On it, in concrete, a few steps in front of the brute: a column 2.6 m
high on its own; a wall of three panels (1.2 m wide, 2.4 high, 0.35
thick); a slab 3.6 m across on four columns 2.2 m high. "Reconstruire"
puts them back and the brute where it started, without loading anything
again (`Main.rebuild`).

## The character

The mannequin and its clips are the free part of Quaternius's Universal
Animation Library (CC0, see `assets/mannequin/SOURCE.md`): one rigged
figure, 46 clips, of which 7 are played. The blows are not from that
library: see below. `scripts/player/character.gd` builds the tree that
blends all of them; `scripts/player/player.gd` moves the capsule and
tells the character how fast it goes, whether it is in the air, and when
it jumps, lands, strikes or kicks.

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
- **Blows made for games.** The four blows come from Quaternius's
  Universal Animation Library 2 (CC0, the free version; see
  `assets/fight/SOURCE.md`): animations drawn for games, with big poses
  and blows that land within a third of a second. Its skeleton is the
  mannequin's own under other names, so `tools/moves/build.py` takes the
  clips over as they are, joins each stroke to its recovery and measures
  it. One was made as a punch (the hook); the others are sword strokes
  thrown without the sword. What is measured on each is stored with it:
  when the fist gets there (the blow counts then), when the next move may
  start, how far and how high it reaches, and which way it is going.
- **What is motion capture.** The kick is what a real person did (CMU
  motion capture database, free to use): the free library has none. The
  tool puts it on the mannequin's skeleton and retimes it (a slow
  wind-up, the last 0.12 s in two thirds of their time, the pose all but
  held for an instant after).
- **The combination.** A lunging hook, a swing up from the right, one
  back across from the left, a leap that comes down fist first, then
  round again. The next blow starts where a stroke ends, and its recovery
  only plays when nothing follows.
- **Steps that are real.** The blows step, some a long way (the swing up
  dashes 1.1 m in, the leap 1.4 m). The steps are on the skeleton's root
  bone; the game moves the body by them (root motion), so a planted foot
  stays planted. A blow is thrown where the stick pushes, or where the
  character faces.
- **The clock of a move.** A fist goes more than a metre between two
  frames of these clips, so the blow has to count on the very step whose
  pose shows it there. A clip starts at the end of the step that takes
  the move up, whoever asked for it (a key between two steps, a button or
  the combination during one): `Character` counts from there, and the
  clips say their blow lands on one of their own frames. `struck` is sent
  before the pose of that step is set: who wants the fist's place reads
  it once the step is over.
- **Stepping up.** Stopped by something no higher than 0.6 m, with room
  above and something flat enough on top, the brute steps onto it
  (`Player._climb`); the view and the body follow over a moment, so that
  they do not jump.

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
