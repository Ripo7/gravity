# Gravity

First-person destruction sandbox in Godot 4.7 (GDScript, Jolt physics).
Charge a violet power ball, throw it, and the impact opens a short-lived
black hole: it pulls the world in, then bursts outward. Everything breaks,
and every piece stays in the world.

## Controls

| Action | Mouse + keyboard | Gamepad |
| --- | --- | --- |
| Move | WASD / arrows (physical keys, works on AZERTY) | Left stick |
| Look | Mouse | Right stick |
| Jump | Space | A / Cross |
| Sprint | Shift | L3 |
| Charge, release to throw | Hold left mouse | Hold RT or RB |
| Reset arena | R | Back / Select |
| Stats overlay | F3 | LB |
| Release mouse | Esc | Start |

## Play builds

- **Browser:** every pull request gets a Vercel preview link (posted on the PR).
  `main` deploys to production.
- **Windows / macOS / Linux:** open the PR's *Checks → CI → Export builds* run
  and download the `gravity-*` artifacts from the run summary.
  The macOS build is ad-hoc signed; right-click → Open the first time.

## How it works

| Piece | File |
| --- | --- |
| Arena layout (move/edit in the editor) | `scenes/main.tscn`, `scripts/destruction/structure.gd` |
| Intact blocks, support/collapse check | `scripts/destruction/structure_set.gd` |
| Loose pieces: pooled server bodies + one MultiMesh | `scripts/destruction/debris_system.gd` |
| Pre-fractured patterns | `scripts/destruction/fracture.gd` |
| Charge → blast tuning in one place | `scripts/power/blast_params.gd` |
| Pull then burst | `scripts/power/gravity_blast.gd` |
| Lens, sparks, shake, slow motion | `scripts/fx/*`, `shaders/*`, `scripts/core/game_world.gd` |

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
- **Look:** clean boxy shards fit the minimal white architecture.

Collapse comes from a support graph: after any break, blocks with no chain of
contacts to the ground are released as whole blocks, which can shatter again.

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
