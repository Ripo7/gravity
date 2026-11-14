# Concept: breaking a house

Two tests in one greybox scene, seen in third person: a house that breaks,
and a character that is animated.

- **Destruction.** Walls break into irregular shards where they are hit, and
  into smaller crumbs where they are hit hardest; what is no longer held up
  falls, and breaks again when it lands. Nothing disappears: the rubble
  stays and you can climb on it. What is shot at it is a plain ball, a
  stand-in.
- **Character animation.** A mannequin that stands, walks, jogs, sprints,
  jumps, lands, puts its arm out to shoot and throws punches, by blending
  ready-made clips; and a second one to punch, which flinches, goes down
  and gets back up.

Godot 4.7, GDScript, Jolt physics, Compatibility renderer (WebGL2), so it
can be played in Safari on an iPhone from each pull request's preview.

The previous project, Gravity, is kept as it was on the branch
[`archive/gravity`](../../tree/archive/gravity).

## Controls

| | Keyboard and mouse | Phone |
| --- | --- | --- |
| Move | WASD (by position, so ZQSD on AZERTY) / arrows | left stick: pushed a little, a walk; fully, a run |
| Sprint | shift | the stick held fully pushed for 0.8 s |
| Look | mouse | drag on the right half |
| Shoot | left click or F | blue button |
| Punch | right click or E | red button |
| Jump | space | small button |
| Rebuild the house | R | "Reconstruire" |

The camera sits behind the character's left shoulder and turns about its
head; it comes closer when a wall is behind (and the character is not
drawn when the camera is right against its back). The character goes where
you push, seen from the camera, and turns to face where it goes. A shot
goes to what is under the crosshair, and the character turns to it. A
punch is a jab; pressed again before it is over, a cross follows, then a
jab, and so on. The red mannequin near where you start is there to take
them.

The line at the top left shows frames per second, the cost of one physics
step and how many pieces there are (and how many are moving).

## The character

The mannequin and its clips are the free part of Quaternius's Universal
Animation Library (CC0, see `assets/mannequin/SOURCE.md`): one rigged
figure, 46 clips, of which 14 are used. `scripts/player/character.gd`
builds the tree that blends them; `scripts/player/player.gd` moves the
capsule and tells the character how fast it goes, whether it is in the
air, and when it jumps, lands, shoots or punches. The dummy
(`scripts/game/dummy.gd`) is the same character in other colours, told
when it is hit and when it goes down.

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

- **Punches.** Two clips, a jab (left) and a cross (right), played a
  little faster than they were made. Three moments were read on each: the
  fist is out (that is when the blow counts), the fist is on its way back
  (from then on the other punch may start, if it was asked for), and the
  fists are back up. After the last punch the guard is held for a second,
  unless you walk away. A punch is thrown where the stick pushes; if an
  opponent is there, within 2.2 m, the character turns to it and steps in
  while the arm goes out, so that the fist arrives on it.
- **Taking a blow.** The dummy flinches (a small clip for a jab, a bigger
  one for a cross or a shot), flashes white and is pushed back a little.
  A jab counts for 1, a cross or a shot for 2; at 6 it falls on its back,
  away from the blow, lies there 2 s and gets up: the fall played
  backwards, since the library has no clip for getting up.

Not there: strafing and walking backwards (the free clips only go
forward, so the character always turns to where it goes, and slides for
half a second when it shoots while running sideways), feet placed on
uneven ground, the head or the arm following the aim up and down. For
fighting: an opponent that hits back, blocking, kicks (no clip), the
dodge roll (there is a clip), punches that break the house. The feet
slide during the step into a punch and when the dummy is pushed back.

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
that leaves your eye at 36 m/s, flies straight and stops at the first thing
it touches. In a standing wall, the shards centred within 0.7 m of the
impact are knocked out (the nearest half in crumbs) and the bonds of those
up to 1.3 m crack; a loose piece is shoved; the ground only stops it. One
shot every 0.3 s.

Quality tiers (`scripts/core/quality.gd`: phone, browser, desktop) change
the dust, the decorative bits and how many crumbs there can be. The house,
its shards and what holds are the same everywhere.

## Run

```sh
godot --path .                                                # play
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn   # tests
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- --only=house
pip install "gdtoolkit==4.*" && gdlint scripts tests && gdformat --check scripts tests
```

`tools/install_godot.sh` downloads the right Godot (and `--templates` the
export templates) into `~/.godot-ci`.

Scripted runs (`scripts/core/director.gd`), on desktop after `--`, in a
browser as `index.html?mode=...`:

```sh
# A fixed tour that takes the house apart, with the cost of the physics.
godot --headless --fixed-fps 60 --path . -- --mode=showcase --seed=1 --prof --quality=low \
  | python3 tools/perf_gate.py
# Your own steps: aim, shoot, wait, run forward...
godot --path . -- --mode=play --from=-2.5,0.05,4.2 --steps="a@-2.5,1.4,-0.6;o;w1;o@-2,2,-0.6;w2;f0.8"
# The character on open ground: walk, run, sprint to the right, jump, shoot.
godot --path . -- --mode=play --from=-25,0.05,30 --steps="p0.2,0,2;p1,0,2;p1,0,2,1;j;w1.5;o;w1"
# A fight: walk up to the dummy, jab, cross, jab, cross, and it goes down.
godot --path . -- --mode=play --from=4,0.05,10.5 --steps="a@4,1.3,7.5;p0,-0.4,0.8;h;w0.25;h;w0.4;h;w0.4;h;w6"
# How loaded the house is as built (1 = a bond breaks).
godot --headless --path . -- --mode=check
```

Add `--write-movie out.avi --fixed-fps 30` before `--path` to record a run.

## Checks

- `tests/`: a small headless runner; files `tests/test_*.gd`, methods
  `test_*` (they may `await`). They cover the cut (volumes, shared faces),
  what holds and what falls, shots at the house, the controls, and the
  character: where the camera sits and how it comes in at walls, the
  character turning to where it goes, its planted foot not sliding from a
  slow walk to a sprint, jumps and landings, the arm going out and the
  shot landing under the crosshair, and the fight: jab then cross then
  guard, the step in and the fist being on the dummy when the blow
  counts, what is out of reach, the dummy going down and getting up, a
  shot hitting it.
- `tools/perf_gate.py`: reads a profiled showcase and fails when the
  physics gets too slow.
- `tools/web_probe.mjs`: loads the web export in headless Chromium, breaks
  the house and fails on any error (`npm install playwright`, then
  `node tools/web_probe.mjs build/web shot.png`). WebGL2 is stricter than
  desktop OpenGL: two bugs only showed there.
- `.github/workflows/ci.yml` runs lint, tests, the perf gate, the web
  export and the probe on every pull request. Vercel builds a preview of
  the web export for every push (`vercel.json`, `tools/vercel_build.sh`).

## Measured

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), phone settings.

The showcase tour of the house (84 shots from 14 places, 1100 to 1250 of
the 1516 shards down, 900 to 1200 pieces and 150 to 560 moving at once),
8 seeds:

- a physics step costs 0.4 to 1.1 ms at the median, and 1.2 to 1.6 ms on
  average while things move;
- 99% of the steps are under 3.6 to 6.8 ms, the slowest takes 5.5 to
  10.7 ms.

The character: a whole frame (one physics step and one idle step, the
house standing, nothing drawn) takes 0.10 to 0.13 ms while it runs, and
0.09 ms with its animation tree switched off: blending the clips costs
about 0.02 to 0.04 ms a frame here. The planted foot slides 0.05 to
0.2 m/s between a slow walk and a run, 0.5 to 1 m/s at a sprint
(7.8 m/s). The dummy, a second body with its own tree, adds 0.03 to
0.05 ms to that frame. Jab, cross, jab, cross puts it down in 1.4 s; it
is back on its feet 4.5 s after the last blow.

Not measured: a real phone. The line at the top left is there for that.

## Assets

`assets/mannequin/`: the mannequin and its animation clips, from
[Quaternius's Universal Animation
Library](https://quaternius.com/packs/universalanimationlibrary.html)
(CC0). Where the files come from, their checksums and the list of clips are
in `assets/mannequin/SOURCE.md`.

`addons/kenney_prototype_textures/`: [Kenney's prototype
textures](https://kenney.nl/assets/prototype-textures) (CC0), as packaged
for Godot by [Calinou](https://github.com/Calinou/kenney-prototype-textures).
Only two are used (`dark/texture_07.png` for the ground,
`light/texture_07.png` for the house), and `export_presets.cfg` leaves the
others out of the web export (1.5 MB instead of 54 MB). **To use another
one, remove it from `exclude_filter` there**, or it will be missing in the
browser only.
