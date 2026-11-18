# Architecture

How the code is laid out and who owns what. What the game is to be is in
[CONCEPT.md](CONCEPT.md); numbers are in [PERFORMANCE.md](PERFORMANCE.md);
where the assets come from is in [CREDITS.md](../CREDITS.md).

The game is at step 1 of its plan: a bare bench and one brute. What
breaks is not written yet. The engine of the version before (boxes cut
into shards bonded together) was taken out with it, on purpose: see the
end of the concept for why, and the branch `archive/v1` for the code.

## Layout

| Where | What |
| --- | --- |
| `scripts/main.gd` | builds the bench: sky, sun, ground, the brute, HUD |
| `scripts/core/` | launch options, input map, collision layers, the physics clock, scripted runs (`director.gd`) |
| `scripts/player/` | `Player` (controls, camera) and `Character` (the animated body) |
| `scripts/fx/` | the round shadow under the brute |
| `scripts/ui/` | HUD and touch controls |
| `scripts/destruction/` | `Fracture`: cuts a box into irregular convex shards. Kept for the blocks concrete breaks into; nothing uses it yet |
| `shaders/` | the ground's grid |
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
  `power`, `way`). It never decides what the blow does: nothing listens
  yet; what breaks will.
- Signals go up, calls go down; a child never calls its parent.

Collision layers (`Layers`): 1 world (the ground, what neither moves nor
breaks), 4 the brute.

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
- Nothing is kept that nothing uses, apart from `Fracture`, which the
  next step takes up.

## The bench

A ground 400 m across, at height 0, in one colour with a line every metre
and a heavier one every five (`shaders/ground.gdshader`, computed per
pixel: no picture). On a bare ground the lines are what shows how fast
and how far the brute goes.

The sun casts no shadow: on the phone the version before was measured on,
its shadows were what cost the most. The brute has a round shadow
(`BlobShadow`) that lies on the ground under it, found by a ray each
physics step, and gets smaller and fainter as the brute goes up.

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
(layer world): the camera stays in front of it, going in at once and
easing back out. With less than 1.4 m behind the shoulder it goes behind
the head instead; closer than 0.7 m it would only see the character's
back, which is then not drawn.
