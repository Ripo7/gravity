# Concept: breaking a house

A first-person destruction test: a small greybox house and one power, a
shock wave. Walls break into irregular shards where they are hit; what is no
longer held up falls, and breaks again when it lands. Nothing disappears:
the rubble stays and you can climb on it.

Godot 4.7, GDScript, Jolt physics, Compatibility renderer (WebGL2), so it
can be played in Safari on an iPhone from each pull request's preview.

The previous project, Gravity, is kept as it was on the branch
[`archive/gravity`](../../tree/archive/gravity).

## Controls

| | Keyboard and mouse | Phone |
| --- | --- | --- |
| Move | WASD (by position, so ZQSD on AZERTY) / arrows | left stick |
| Look | mouse | drag on the right half |
| Shock wave | left click or F | blue button |
| Jump | space | small button |
| Rebuild the house | R | "Reconstruire" |

The line at the top left shows frames per second, the cost of one physics
step and how many pieces there are (and how many are moving).

## How the destruction works

1. **Cut once, at load** (`scripts/destruction/fracture.gd`). Every box of
   the house (wall, slab, pillar) is cut into convex shards about 0.6 m
   across, of mixed sizes, by a Voronoi diagram. Neighbours share exactly
   the same corners, so an intact wall has no gaps. The house is 1432 shards
   and is cut in about 0.2 s (0.5 s in a browser).
2. **Bonds** (`structure.gd`). Shards that touch are bonded, with the area
   they share; so are the shards of two boxes that touch. Shards on the
   ground are anchors.
3. **What holds** (`support.gd`). After any damage, a look at the bonds
   finds what is still tied to the ground (the rest comes off, in rigid
   chunks of 45 shards at most) and how loaded each bond is: weight hangs
   on the bonds below, and overhangs pull harder the farther they stick
   out. Overloaded bonds break, so a balcony without its pillars comes down
   by itself, a bit at a time. The look is spread over several physics
   steps (about 1 ms each), and so is a big fall (40 shards per step).
4. **Pieces** (`pieces.gd`). What comes off is a rigid body made of its
   shards' convex shapes. When a piece loses speed in a hit, the energy
   lost crushes that much of it into single shards around the contact and
   cracks the rest, and it splits along the broken bonds; half goes into
   the building if that is what it hit. Pieces that lie still are frozen
   (static) and wake when something near them moves.
5. **One draw call** (`shard_mesh.gd`, `shaders/shards.gdshader`). All the
   shards are one mesh; a small texture tells the vertex shader which body
   each shard follows and where that body is. The checker is laid from the
   place a shard had in the house, so it stays on the pieces. Cut faces are
   dark, and only drawn once the two shards are apart.
6. **Collisions of what stands.** A whole box collides as a few plain
   blocks; the first shard to leave a block turns it into one static shape
   per shard, so the holes are real.

The shock wave (`scripts/powers/shockwave.gd`) is a 32° cone, 16 m long,
whose front moves at 45 m/s. It tears out the shards it hits hard enough,
cracks the bonds of the others, and is mostly stopped by what holds: a wall
shelters what is behind it, a hole lets it through.

Quality tiers (`scripts/core/quality.gd`: phone, browser, desktop) only
change the dust and the decorative bits. The house and its physics are the
same everywhere.

## Run

```sh
godot --path .                                                # play
godot --headless --path . res://tests/test_runner.tscn        # tests
godot --headless --path . res://tests/test_runner.tscn -- --only=house
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
# Your own steps: aim, shock wave, wait, walk forward...
godot --path . -- --mode=play --from=-2.5,0.05,4.2 --steps="a@-2.5,1.4,-0.6;o;w2;f0.8;o;w3"
# How loaded the house is as built (1 = a bond breaks).
godot --headless --path . -- --mode=check
```

Add `--write-movie out.avi --fixed-fps 30` before `--path` to record a run.

## Checks

- `tests/`: a small headless runner; files `tests/test_*.gd`, methods
  `test_*` (they may `await`). They cover the cut (volumes, shared faces),
  what holds and what falls, the shock wave on the house, and the controls.
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

Headless on a 2-core cloud machine, phone settings, the showcase tour
(14 shock waves, 800 to 1100 of the 1432 shards down, up to 700 pieces and
400 moving at once), 6 seeds:

- a physics step costs 0.9 to 1.3 ms at the median, 2.0 to 2.5 ms on
  average while things move;
- 99% of the steps are under 5 to 7 ms, the slowest takes 7 to 12 ms: mostly
  the physics engine with 300 to 400 pieces moving at once (the scripts
  are 1 to 3 ms of such a step);
- the same tour of the archived Gravity (another scene, so only an order of
  magnitude) averaged 5 ms per step while things moved.

Not measured: a real phone. The line at the top left is there for that.

## Textures

`addons/kenney_prototype_textures/`: [Kenney's prototype
textures](https://kenney.nl/assets/prototype-textures) (CC0), as packaged
for Godot by [Calinou](https://github.com/Calinou/kenney-prototype-textures).
Only two are used (`dark/texture_07.png` for the ground,
`light/texture_07.png` for the house), and `export_presets.cfg` leaves the
others out of the web export (1.5 MB instead of 54 MB). **To use another
one, remove it from `exclude_filter` there**, or it will be missing in the
browser only.
