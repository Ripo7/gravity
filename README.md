# Gravity

First-person demolition game in Godot 4.7 (GDScript, Jolt physics).
Charge a violet power ball, throw it, and the impact opens a short-lived
black hole: it pulls the world in, then bursts outward. Buildings obey
real support rules: cut the base and they topple, overload the columns and
the floors pancake, and what falls breaks whatever it lands on.

**Game:** 10 demolition levels with limited charges and 1 to 3 stars for the
share destroyed (unused charges add score), plus an unlimited sandbox.
Progress is saved locally.

## Controls

| Action | Mouse + keyboard | Gamepad |
| --- | --- | --- |
| Move | WASD / arrows (physical keys, works on AZERTY) | Left stick |
| Look | Mouse | Right stick |
| Jump | Space | A / Cross |
| Sprint | Shift | L3 |
| Charge, release to throw | Hold left mouse | Hold RT or RB |
| Restart level | R | Back / Select |
| Pause | Esc | Start |
| Stats overlay | F3 | LB |

**Phones and tablets** (landscape): drag the left half to move (the stick appears
under your thumb), drag the right half to look, hold the violet button to charge
and release to throw, tap the arrow to jump, II to pause.

## Play builds

- **Browser:** every pull request gets a Vercel preview link (posted on the PR).
  `main` deploys to production.
- **Windows / macOS / Linux:** open the PR's *Checks → CI → Export builds* run
  and download the `gravity-*` artifacts from the run summary.
  The macOS build is ad-hoc signed; right-click → Open the first time.

## How it works

| Piece | File |
| --- | --- |
| Levels (open in the editor; structures preview) | `levels/*.tscn`, `scripts/game/level.gd`, `scripts/destruction/structure.gd` |
| Level flow, stars, score, callouts | `scripts/game/level_run.gd`, `scripts/game/game_state.gd` |
| Menu (live attract-mode backdrop) | `scenes/menu.tscn`, `scripts/ui/main_menu.gd` |
| Structural physics: health, loads, toppling, falling pieces | `scripts/destruction/structure_set.gd` |
| Loose pieces: pooled server bodies + one MultiMesh | `scripts/destruction/debris_system.gd` |
| Pre-fractured patterns | `scripts/destruction/fracture.gd` |
| Concrete / wood / metal: look, weight, strength, breakage | `scripts/destruction/materials.gd`, `shaders/block.gdshader` |
| Charge → blast tuning in one place | `scripts/power/blast_params.gd` |
| Pull then burst | `scripts/power/gravity_blast.gd` |
| Lens, sparks, dust, chips, shake, slow motion | `scripts/fx/*`, `shaders/*`, `scripts/core/game_world.gd` |
| Sound effects (synthesised, regenerate with `python3 tools/make_sounds.py`) | `audio/*.wav`, `scripts/core/sfx.gd` |

### Why pre-fractured box pieces (not runtime Voronoi)

Each block breaks into a cached recursive-split pattern of smaller boxes.

- **Physics cost:** box–box contacts are the cheapest shape pair in Jolt.
  Voronoi pieces need convex hulls, which are several times slower per contact
  and tend to jitter when they pile up.
- **Draw cost:** every piece is the same unit cube scaled per instance, so all
  debris renders in **one draw call**. Voronoi pieces are unique meshes,
  so each needs its own draw call. That is what limits WebGL first.
- **Break cost:** a break is a cache lookup plus spawning pooled bodies.
  Runtime Voronoi has to generate meshes, hulls and colliders on the frame of
  the hit, which stalls the browser build at exactly the most exciting moment.
- **Look:** clean boxy shards fit the block architecture. Each material
  breaks its own way: concrete into many chunks, wood into long splinters
  along the grain, metal into a few heavy plates (and it is often knocked
  loose whole).

### Structural physics

After anything changes, each structure is re-checked:

1. **Connected pieces.** A piece with no contact to the ground falls as one
   rigid body (a compound of its blocks) and breaks apart where it lands.
2. **Toppling.** If a grounded piece's centre of mass leaves the footprint it
   stands on, it tips over as one body.
3. **Loads.** Weight flows top-down from each block to the blocks it rests on,
   split by contact area. Capacities are calibrated on the intact structure
   (safety factor 2 for concrete, 1.8 wood, 2.8 metal), so a building stands
   until enough supports are lost; then the most overloaded blocks crush, a
   few per frame, and the collapse spreads floor by floor.
4. **Impacts.** A falling piece damages the blocks it hits (heavier hits
   harder), so towers can be toppled into each other.

Blocks keep their damage between blasts (shown as cracks), which lowers
their capacity.

### Performance budget

- Pieces are raw `PhysicsServer3D` bodies (no nodes), created once and pooled.
- Sleeping pieces are skipped every frame; Jolt sleeps them after 0.4 s at rest.
- Budget: 2000 pieces on desktop, 900 on web. When full, the oldest sleeping
  piece is recycled. On web, pieces also expire after 120 s.
- Run the benchmark: `godot -- --mode=bench` (desktop) or open the web build with `?mode=bench`
  (web). CI runs the web one in headless Chromium and prints it in the job summary.

## Develop

```sh
tools/install_godot.sh                     # official 4.7.2 editor into ~/.godot-ci
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn   # tests
pip install "gdtoolkit==4.*" && gdlint scripts tests && gdformat --check scripts tests
godot --path . -- --mode=showcase --shots=/tmp/shots     # scripted blasts + screenshots
```

Workflow: branch → pull request → CI (lint, headless tests, exports, web
benchmark) and a Vercel preview → merge.
