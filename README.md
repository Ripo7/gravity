# Concept: breaking a house

A first-person destruction test, and nothing else yet: a small greybox
house and something to shoot at it with (a plain ball, a stand-in). Walls
break into irregular shards where they are hit, and into
smaller crumbs where they are hit hardest; what is no longer held up falls,
and breaks again when it lands. Nothing disappears: the rubble stays and you
can climb on it.

Godot 4.7, GDScript, Jolt physics, Compatibility renderer (WebGL2), so it
can be played in Safari on an iPhone from each pull request's preview.

The previous project, Gravity, is kept as it was on the branch
[`archive/gravity`](../../tree/archive/gravity).

## Controls

| | Keyboard and mouse | Phone |
| --- | --- | --- |
| Move | WASD (by position, so ZQSD on AZERTY) / arrows | left stick |
| Look | mouse | drag on the right half |
| Shoot | left click or F | blue button |
| Jump | space | small button |
| Rebuild the house | R | "Reconstruire" |

The line at the top left shows frames per second, the cost of one physics
step and how many pieces there are (and how many are moving).

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
# Your own steps: aim, shoot, wait, walk forward...
godot --path . -- --mode=play --from=-2.5,0.05,4.2 --steps="a@-2.5,1.4,-0.6;o;w1;o@-2,2,-0.6;w2;f0.8"
# How loaded the house is as built (1 = a bond breaks).
godot --headless --path . -- --mode=check
```

Add `--write-movie out.avi --fixed-fps 30` before `--path` to record a run.

## Checks

- `tests/`: a small headless runner; files `tests/test_*.gd`, methods
  `test_*` (they may `await`). They cover the cut (volumes, shared faces),
  what holds and what falls, shots at the house, and the controls.
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
(`--fixed-fps 60`), phone settings, the showcase tour (84 shots from 14
places, about 1300 of the 1516 shards down, 900 to 1300 pieces and 190 to
310 moving at once), 8 seeds:

- a physics step costs 0.7 to 1.0 ms at the median, and 1.3 to 1.6 ms on
  average while things move;
- 99% of the steps are under 3.8 to 4.6 ms, the slowest takes 5.5 to
  7.5 ms.

The tour is not the one of earlier versions (14 shock waves, which brought
down more at once), so these figures do not compare with theirs.

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
