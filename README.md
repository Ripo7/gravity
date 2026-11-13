# Concept: breaking a house

A first-person destruction test: a small greybox house, one power (a shock
wave) and an orb that swallows the debris when you want it gone. Walls break into irregular shards where they are hit, and into
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
| Shock wave | left click or F | blue button |
| Orb | hold right click or E | hold the violet button |
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
5. **Crumbs.** A shard that is hit hard (the middle of a close blast, a
   lone shard that lands or is thrown against something at 6 m/s or more,
   the point where a falling piece strikes) is cut once more, there and
   then, into 2 to 6 crumbs that fill it exactly. Each crumb is one more
   body, so they are rationed: 3 shards per step, none while more than 260
   pieces are moving, and no more than a fixed number at a time (250 on a
   phone, 450 in a browser, 800 on a desktop), with fewer and fewer made as
   that fills up. Crumbs the orb swallows leave their room to new ones.
6. **Two draw calls** (`shard_mesh.gd`, `shaders/shards.gdshader`). All the
   shards are one mesh; a small texture tells the vertex shader which body
   each shard follows and where that body is. The checker is laid from the
   place a shard had in the house, so it stays on the pieces. Faces made by
   a cut are only drawn once the two shards are apart; their middle is
   pushed in or out and each facet is lit on its own, like broken stone.
   The crumbs are a second, small mesh drawn the same way, made again when
   some are added, without those that are gone.
7. **Collisions of what stands.** A whole box collides as a few plain
   blocks; the first shard to leave a block turns it into one static shape
   per shard, so the holes are real. A shard torn out by a blast goes
   through what still stands for 5 steps: with leaning cuts it would often
   be wedged in its own hole.

The shock wave (`scripts/powers/shockwave.gd`) is a 32° cone, 16 m long,
whose front moves at 45 m/s. It tears out the shards it hits hard enough,
cracks the bonds of the others, and is mostly stopped by what holds: a wall
shelters what is behind it, a hole lets it through.

The orb (`scripts/game/orb.gd`) is not a power: it breaks nothing. While
you hold the button, a ball of magic stays open in front of you, a little
below where you look. Loose pieces within 11 m that it can see (not what is
behind a wall) rise, wind in and dwindle into it, 16 at a time, and are gone
for good: no body, not drawn. Let go and it closes; what was on its way in
falls back. This is the one place where debris disappears, and only because
you ask: the volume swallowed is still counted, and the crumbs swallowed
leave their room to new ones. Pieces on their way in are on a collision
layer of their own, so that you are not carried off standing on one.

Quality tiers (`scripts/core/quality.gd`: phone, browser, desktop) change
the dust, the decorative bits and how many crumbs there can be. The house,
its shards and what holds are the same everywhere.

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
# Your own steps: aim, shock wave, wait, walk forward, orb open (g) and let go (t)...
godot --path . -- --mode=play --from=-2.5,0.05,4.2 --steps="a@-2.5,1.4,-0.6;o;w2;f0.8;o;w3"
godot --path . -- --mode=play --from=0,0.05,8.5 --steps="o@-1.5,1.4,2.7;w2;g;w4;t;w2"
# How loaded the house is as built (1 = a bond breaks).
godot --headless --path . -- --mode=check
```

Add `--write-movie out.avi --fixed-fps 30` before `--path` to record a run,
and `--touch` after `--` to see the thumb controls on a desktop.

## Checks

- `tests/`: a small headless runner; files `tests/test_*.gd`, methods
  `test_*` (they may `await`). They cover the cut (volumes, shared faces),
  what holds and what falls, the shock wave on the house, the orb, and the
  controls.
- `tools/perf_gate.py`: reads a profiled showcase and fails when the
  physics gets too slow.
- `tools/web_probe.mjs`: loads the web export in headless Chromium, breaks
  the house, opens the orb on the debris, and fails on any error (`npm install playwright`, then
  `node tools/web_probe.mjs build/web shot.png`). WebGL2 is stricter than
  desktop OpenGL: two bugs only showed there.
- `.github/workflows/ci.yml` runs lint, tests, the perf gate, the web
  export and the probe on every pull request. Vercel builds a preview of
  the web export for every push (`vercel.json`, `tools/vercel_build.sh`).

## Measured

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), phone settings, the showcase tour (14 shock waves, about
1050 of the 1516 shards down, up to 950 pieces and 450 to 500 moving at
once), 8 seeds, twice:

- a physics step costs 1.4 ms at the median, and 1.8 to 2.4 ms on average
  while things move depending on the seed (1.9 over all of them);
- 99% of the steps are under 6 to 9.5 ms (7 over all seeds), the slowest
  takes 10 to 13 ms: mostly the physics engine with 300 to 500 pieces
  moving at once;
- the same runs before leaning cuts and crumbs: 1.8 ms on average, 99%
  under 5.7 ms. So the finer rubble costs about 5% on average and 20 to 30%
  on the slowest steps;
- browser settings (450 crumbs instead of 250): 2.0 to 2.3 ms on average,
  99% under 7 to 9 ms (3 seeds);
- the same kind of tour of the archived Gravity (another scene, measured in
  real time, so only an order of magnitude) averaged 5 ms per step while
  things moved.

The orb, same machine and settings (the balcony brought down, then the orb
held open for 7 s): 0.2 to 0.4 ms per step while it draws debris in, and
the 300 loose pieces become about 115.

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
