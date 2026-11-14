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
| `scripts/game/` | the level (`House`), what the brutes have in common (`Fighter`), the other brute (`Brute`), the ball (`Projectile`) |
| `scripts/player/` | `Player` (controls, camera) and `Character` (the animated body, shared by both brutes) |
| `scripts/fx/`, `scripts/ui/` | dust and chips; HUD and touch controls |
| `shaders/` | the one shader that draws every shard |
| `assets/` | the mannequin and the boxing moves (made by `tools/mocap`) |
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
the steps of a boxing move reach the capsule at the same pace), then
`Structure` spreads what it has to do (what holds, what falls) over the
step. Collision layers: 1 world, 2 structure, 3 debris, 4 player, 5 actor
(the other brute); a body off its feet keeps only the ground.

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
figure, 46 clips, of which 11 are used. The boxing moves are not from
that library: they are motion capture (see below).
`scripts/player/character.gd` builds the tree that blends all of them;
`scripts/player/player.gd` moves the capsule and tells the character how
fast it goes, whether it is in the air, and when it jumps, lands, shoots,
punches, kicks or ducks. The other brute (`scripts/game/brute.gd`) is the
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
- **The arm that shoots.** The casting clip is laid over whatever the legs
  do, on the left arm and the chest only; the body turns a little so that
  the arm points at what is aimed at.

- **Boxing, from motion capture.** The guard, the punches, the duck and
  the kick are what real people did: a boxer shadow-boxing and a karateka,
  recorded in the CMU motion capture database (free to use, see
  `assets/boxing/SOURCE.md`). `tools/mocap/build.py` reads the takes, puts
  them on the mannequin's skeleton (every bone takes the turn its joint
  made since the T pose; the hips go where the hip joints were, scaled by
  the length of the legs), cuts the moves out and writes one animation
  library. What it measures on each move is stored with it: when the fist
  or foot gets there (the blow counts then), when the next move may start,
  how far it reaches.
- **The combination.** Jab and cross are one passage of the take, cut in
  two between the punches, and so are the left and the right to the body:
  chained, the motion is the boxer's own, weight going from one foot to
  the other. Pressed once, a punch runs into the guard instead.
- **Steps that are real.** A boxer steps with his punches. Those steps are
  taken out of the pose and given to the skeleton's root bone; the game
  moves the body by them (root motion), so a foot that is planted in the
  capture is planted in the game. A strike also goes for the opponent in
  front: the character turns to it, and if the fist would stop short it
  is carried the rest of the way while the arm goes out (that part
  slides).
- **Blows.** When a fist or a foot gets there, the other brute takes it
  if it is in front and within reach. A jab, a cross and the left to the
  body make it flinch (a small clip or a bigger one), flash white and
  step back. The right to the body, which ends the combination, and the
  kick throw it: 12 m/s along the ground, 4 up.
- **Thrown.** A brute off its feet goes over backwards and flies, back
  first. Nothing that stands stops it: every step of its flight, the
  shards within 0.95 m of its middle are knocked out (the nearest in
  crumbs), each one taking a little of its speed, so it goes through a
  wall, across a room and out through the next. It lands, slides, lies
  0.7 s and gets up (the fall played backwards, the library having no
  clip for getting up).
- **Fists break what stands.** A strike that reaches a wall or a pillar
  knocks out what is within 0.45 m of a jab, 0.7 m of a punch, 1 m of a
  kick, and sends off the loose pieces that lie there.
- **The other brute** has no plan: it walks straight at you, stops at
  arm's length, and after a wait of 0.5 to 1.3 s kicks (3 times in 10) or
  throws one to four punches of the combination. It steps onto rubble;
  stopped by a wall for a third of a second, it kicks it in and goes
  through. From behind the house it reaches you in front of it in about
  12 s, 38 shards knocked out on the way.

Not there: strafing and walking backwards (the free clips only go
forward, so the character always turns to where it goes, and slides for
half a second when it shoots while running sideways), feet placed on
uneven ground, the head or the arm following the aim up and down. For
the fight: no health and no end (it goes on until the house is gone),
moving around in the guard (the stance is dropped to walk), blocking,
hooks and uppercuts to the head, a real tumble in the air (the thrown
body holds one pose), the brutes being any bigger than people. The
brutes stand upright when hit and the boxer crouches, so punches land on
the chest. After the kick the leg comes back by a blend, not by the
karateka's own step. A thrown body passes through loose rubble.


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
5. **Crumbs.** A shard that is hit hard (where a shot lands, a
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

The projectile (`scripts/game/projectile.gd`) is a placeholder: a ball
that leaves the character's chest at 36 m/s, flies straight and stops at the first thing
it touches. In a standing wall, the shards centred within 0.7 m of the
impact are knocked out (the nearest half in crumbs) and the bonds of those
up to 1.3 m crack; a loose piece is shoved; the ground only stops it. One
shot every 0.3 s.

Quality tiers (`scripts/core/quality.gd`: phone, browser, desktop) change
the dust, the decorative bits and how many crumbs there can be. The house,
its shards and what holds are the same everywhere.
