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
blow. Two matters so far: concrete, which breaks, and metal, which
bends.

### What all matters share

1. **Pieces** (`Structure.add_piece`). A piece is an upright box: a
   column, a slab, a wall. While it stands whole it is one static box
   for the physics.
2. **A blow harms the place it lands on**, not the whole piece. What a
   place takes belongs to the piece (`Matter.strength`): so many points
   of blows for each metre the piece is thick the way it is thinnest,
   22.5 for concrete, so 9 for a column 0.4 m thick; 70 for metal, so 14
   for a post 0.2 m thick. A blow is 2 points, a heavy one (the last of
   the combination, the kick) 3. How the piece is cut or drawn changes
   nothing to it.
3. **What is no longer carried comes down** (`Structure._settle`). A
   piece rests on the pieces right under it. When something under it
   goes, what is left of it is looked at again, and so on up through
   what rests on it. A slab or a metal piece holds if it stands on the
   ground or if its middle is still over what is left under it (a slab
   holds on three columns, not on two on the same side: `_held`);
   otherwise it comes down in one, a loose body. (A wall or a column is
   looked at block by block, and a metal plate sags: see below.)
4. **Only a blow breaks or bends.** From the brute: `Structure.strike`
   follows the fist from the body to where it ends; the first piece on
   its way takes the blow, there, and what lies loose near the end is
   sent off (not far: it is heavy). Or from something heavy that lands
   on a piece (`Rubble._land`): a point for each 900 kg.m/s it loses
   against it, where it lands, and only on a face that looks up. What
   brushes past a wall on its way down does nothing to it. Walking,
   running and jumping break nothing: what stands is a wall to the
   brute.
5. **The rubble** (`Rubble`). Loose bodies are made straight on the
   physics server, no nodes. They fall at a share of real gravity
   (`fall`, 0.3 to begin with, set by the slider): slowly, which is what
   makes the brute a giant. Speeds told "as at real gravity" in the code
   go with the square root of that share, so the same things happen at
   any setting, only slower. A body that touches something and has been
   still for half a second is frozen (static): a heap costs nothing,
   stays put, and the brute steps onto it. It moves again when a piece
   near it breaks or when a blow lands by it. Nothing rests on the brute
   itself: what comes down on it pushes it out from under
   (`Rubble.bears_down`, `Player.give_way`).
6. **One draw call** (`ShardMesh`, `shaders/shards.gdshader`). Everything
   is in one mesh that never changes; a small texture says which body
   each part goes with (and how far it is pushed in, for a dent) and
   another where each body is.

### Concrete: it cracks where it is struck, then lets go there

1. **Cut once, when it is made** (`Fracture`, `Matter.grain`). Each piece
   is cut into a few irregular convex blocks, about 0.7 m across (about
   what a blow knocks out), bigger if that would make more than sixteen:
   4 for the column, 15 for the wall, 16 for the slab.
2. **Places** (`Structure.hit`, `_wound`). A blow lands on a place: one
   the piece has been struck at within 0.6 m of there, or a new one.
   What the place has taken is what counts, not what the piece has taken
   in all. The blocks round it (the nearest, and those whose middle is
   within 0.6 m) show cracks (`_crack`): each is drawn a little smaller
   and askew, the gaps dark, wider from half the strength on. The others
   show nothing.
3. **Letting go** (`Structure._expel`). When the place has taken what the
   piece can take, those blocks are knocked out, away from the blow, at
   4.5 m/s as at real gravity: loose bodies, and a hole. For half a
   second what is left of the piece does not stop them (`Rubble.
   let_through`): cut every which way, a block would stay caught in its
   hole. From under something the piece carried, they hardly rub on
   anything for 0.45 s and slide out (`Rubble.slip`). What stands of the
   piece is, from then on, the blocks that are left, each in the way as
   it is (`_refresh`).
4. **What holds** (`Structure._unheld`, for a wall or a column). A block
   holds if it sits on something: the ground or what stands under the
   piece, or a block right under it that sits. Or if it is between two
   blocks that sit, right beside it on each side and no more than a
   metre apart: the lintel over a hole one block wide. Over a wider hole
   what is left comes down: two holes side by side at the foot of a wall
   open it to the top. Which blocks are right under and right beside
   which is worked out once, when the piece is cut (`_lay_courses`), so
   that it does not hang on the luck of the cut.
5. **Coming down in one** (`Structure._fall`, `break_up`). What no
   longer holds comes down as one loose body, the blocks that hold
   together through their cuts. Cut off by a blow, it starts off going
   over away from it. It breaks into its blocks when something stops it
   once it has come down 0.3 m. A slab that loses its columns comes down
   the same way, whole.
6. **All at once** (`Structure.shatter`). A blow that lands nowhere in
   particular (`hit` without a place: the measure, some tests) is taken
   by the whole piece, which cracks all over and, at its strength, goes
   over and comes apart, as every piece did before places.

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

Not there: what falls does nothing to the brute but push it (a deck that
comes down round a brute that cannot get out stays on its head); blocks
that lie in one come apart under blows only once they have taken the
strength of their piece in all; a hole is as big as the blocks round it,
one to three of them, not a fist's exact shape; what holds over a hole
goes by which block is over which, not by weight; a slab that tips onto
what is left under it can stay whole, leaning; metal that lies there no
longer takes a mark; a sheet that stands dented is
still a flat wall to the brute; a plate takes nothing from a blow; the
brute's fists all land between 0.7 and 1 m up, so a post it strikes has
one kink; pieces are upright boxes, turned about the vertical at most.

## The bench

A ground 400 m across, at height 0, in one colour with a line every metre
and a heavier one every five (`shaders/ground.gdshader`, computed per
pixel: no picture). On a bare ground the lines are what shows how fast
and how far the brute goes.

The sun casts no shadow: on the phone the version before was measured on,
its shadows were what cost the most. The brute has a round shadow
(`BlobShadow`) that lies on the ground under it, found by a ray each
physics step, and gets smaller and fainter as the brute goes up.

On it, a few steps in front of the brute, the same three things twice.
In concrete, on its right: a column 2.6 m high on its own; a wall in one
piece (3.6 m wide, 2.4 high, 0.35 thick: wide enough to keep a hole); a
slab 3.6 m across on four columns 2.2 m high. In metal, on its left: a post 0.2 m thick; a
fence of three sheets 0.08 m thick; a deck 0.12 m thick on four posts.
"Reconstruire" puts them back and the brute where it started, without
loading anything again (`Main.rebuild`).

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
