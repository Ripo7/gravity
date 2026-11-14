# Architecture

How the code is laid out, who owns what, and how the two systems that
matter (what breaks, what moves) work. Numbers are in
[PERFORMANCE.md](PERFORMANCE.md); where the assets come from is in
[CREDITS.md](../CREDITS.md).

## Layout

| Where | What |
| --- | --- |
| `scripts/main.gd` | builds the scene: sky, ground, house, the two brutes, HUD |
| `scripts/core/` | launch options, input map, quality tiers, the physics clock, scripted runs (`director.gd`) |
| `scripts/destruction/` | what stands and how it breaks: `Fracture`, `Structure`, `Support`, `Pieces`, `ShardMesh` |
| `scripts/game/` | the level (`House`), what the brutes have in common (`Fighter`), the other brute (`Brute`) |
| `scripts/player/` | `Player` (controls, camera) and `Character` (the animated body, shared by both brutes) |
| `scripts/fx/`, `scripts/ui/` | dust and chips; HUD and touch controls |
| `shaders/` | the one shader that draws every shard |
| `assets/` | the mannequin and the fighting moves (made by `tools/mocap`) |
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
figure, 46 clips, of which 10 are played. The blows are not from that
library: they are motion capture (see below).
`scripts/player/character.gd` builds the tree that blends all of them;
`scripts/player/player.gd` moves the capsule and tells the character how
fast it goes, whether it is in the air, and when it jumps, lands,
strikes, kicks or ducks. The other brute (`scripts/game/brute.gd`) is the
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
- **Blows, from motion capture.** The stance, the three blows, the kick
  and the duck are what real people did, recorded in the CMU motion
  capture database (free to use, see `assets/fight/SOURCE.md`). They were
  picked for weight, not for technique: a strong man waiting (the
  stance), a boxer's long right, a baseball swing without the bat (both
  fists across), wood being chopped without the axe (both fists from
  overhead), a karateka's front kick, a boxer ducking.
  `tools/mocap/build.py` reads the takes, puts them on the mannequin's
  skeleton (every bone takes the turn its joint made since the T pose;
  the hips go where the hip joints were, scaled by the length of the
  legs), cuts the moves out, turns each so that its blow goes straight
  ahead, slows its wind-up and its recovery (the last tenth of a second
  before the blow lands is as performed) and writes one animation
  library. What it measures on each move is stored with it: when the fist
  or foot gets there (the blow counts then), when the next move may start,
  how far and how high it reaches.
- **The combination.** A long right, both fists across, both from
  overhead, then round again. They are three takes of three people, so
  one runs into the next by a blend, not by one person's own motion.
  Pressed once, a blow runs into the stance instead.
- **Steps that are real.** Those people step with their blows. The steps
  are taken out of the pose and given to the skeleton's root bone; the
  game moves the body by them (root motion), so a foot that is planted in
  the capture is planted in the game. A strike also goes for the opponent
  in front: the character turns to it, and if the fist would stop short
  it is carried the rest of the way while the arm goes out (that part
  slides). A blow under way is not cut short by stepping off a heap of
  rubble, and its steps go up onto rubble like any others.
- **Blows.** When a fist or a foot gets there, the other brute takes it
  if it is in front and within reach. The long right and the swing make
  it flinch, flash white and step back. The blow from overhead, which
  ends the combination, and the kick throw it: 12 m/s along the ground, 4
  up. Ducking lets a blow higher than 1.2 m go over, but not the one that
  comes down from overhead.
- **Locking on** (`Player.lock`; the fight starts locked). The nearest
  other brute is marked with a ring, the camera turns to it and stays on
  it, and a strike always goes to it. If the blow would not land from
  where the character stands (the other is farther than its reach and a
  step of 0.5 m, or something stands between them at chest height), the
  character sprints at it first and strikes when it would: no blow is
  thrown at nothing. Held up 0.15 s on the way by what stands, it goes
  through: a hole its size (`Fighter.breach`, the one the other brute
  makes). It gives up after 4 s; ducking or jumping calls the run off.
- **Thrown.** A brute off its feet goes over backwards and flies, back
  first. Nothing that stands stops it: every step of its flight, the
  shards within 0.95 m of its middle are knocked out (the nearest in
  crumbs), each one taking a little of its speed, so it goes through a
  wall, across a room and out through the next. It lands, slides, lies
  0.7 s and gets up (the fall played backwards, the library having no
  clip for getting up).
- **Fists break what stands.** A strike that reaches a wall or a pillar
  knocks out what is within 0.7 m of a blow, 1 m of the blow from
  overhead or of a kick, and sends off the loose pieces that lie there.
- **The other brute** has no plan: it walks straight at you, stops at
  arm's length, and after a wait of 0.5 to 1.3 s kicks (3 times in 10) or
  throws one to three blows of the combination. It steps onto rubble;
  stopped by a wall for a third of a second, it kicks it in and goes
  through. From behind the house it reaches you in front of it in 9 to
  10 s, 27 to 38 shards knocked out on the way.

Not there: strafing and walking backwards (the free clips only go
forward, so the character always turns to where it goes), feet placed on
uneven ground. For the fight: no health and no end (it goes on until the
house is gone), moving around in the stance (it is dropped to walk),
blocking, a real tumble in the air (the thrown body holds one pose), the
brutes being any bigger than people. Locked on, the camera cannot be
turned and there is no circling around the other. Between two blows of
the combination the weight does not shift as one person's would. A
thrown body passes through loose rubble; a brute that stands is still
pushed a little by a piece that lands against it.


## How the destruction works

1. **Cut once, at load** (`scripts/destruction/fracture.gd`). Every box of
   the house (wall, slab, pillar) is cut into convex shards about 0.6 m
   across, of mixed sizes, by a Voronoi diagram. Across a thin box distances
   count for more, so the cuts lean instead of going square through a wall,
   and a pillar also splits along its length. Neighbours share exactly the
   same corners, so an intact wall has no gaps. The house is 1516 shards and
   is cut in about 0.25 s (0.6 s in a browser); rebuilding it reuses the
   cut.
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
