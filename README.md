# Gravity

First-person destruction game in Godot 4.7 (GDScript, Jolt physics).
You have overpowered powers and one building to bring down, without
getting crushed by what falls.

**Le Palais:** a Renaissance palace (about 34 × 26 m, three storeys round an
arcaded courtyard, a loggia, a deep cornice, a tile roof) and its brick
campanile (45 m to the cross) at one corner, alone on a paved square.
Beyond the square, only the plain fading into the haze. Walk in through the
portal and across the courtyard; cut the foot of the tower and it falls on
the palace.

**Powers** (each with its own cooldown):

1. **Black hole** – a black ball opens where you aim. Everything inside its
   radius is torn loose and orbits it fast; there is no explosion. The band
   just outside the radius (red ring) is not pulled but takes damage –
   including you.
2. **Shield** – not aimed: pressing its button makes a tall, curved shell of
   black ice (close to a half dome, but lumpy) burst out of the ground around
   your front. It stops debris and falling pieces until it breaks; its shards
   never hurt you.

**Rules:** you are fragile. Anything heavy that hits you (debris, stones,
collapsing floors), the black hole's band and hard landings hurt; health
comes back after a few seconds without being hit. When you go down you
respawn at the start. No score, no counter: the HUD shows only your health.

## Controls

| Action | Mouse + keyboard | Gamepad |
| --- | --- | --- |
| Move | WASD / arrows (physical keys: ZQSD on AZERTY) | Left stick |
| Look | Mouse | Right stick |
| Jump / sprint | Space / Shift | A / L3 |
| Black hole | Left mouse | RT |
| Shield | Right mouse, E, 2 | LT, LB, RB |
| Restart · pause · stats | R · Esc · F3 | Back · Start |

**Phones and tablets** (landscape): left thumb moves, drag on the right to
aim, the violet button opens a black hole, the shield button next to it
raises the shield, arrow to jump, II to pause.

## Play builds

- **Browser:** every pull request gets a Vercel preview link (posted on the PR).
  `main` deploys to production.
- **Windows / macOS / Linux:** open the PR's *Checks → CI → Export builds* run
  and download the `gravity-*` artifacts from the run summary.
  The macOS build is ad-hoc signed; right-click → Open the first time.

## Making it look good on phones

Physics, not drawing, is what limits the game, so the effects are built to
cost as little of it as possible:

- Only big pieces are physics bodies. Gravel, splinters and glass shards are
  chips with no collision (an arc, one bounce on the surface below, rest),
  and they stay on the ground as the rubble field's gravel.
- What the black hole grinds down becomes grains of a cloud swirling round
  it: thousands of grains moved entirely by their shader (one draw call, no
  physics), flung out as dust and gravel when it closes.
- Broken pieces are shards cut in Blender, but they share one mesh: the
  shader moves its vertices to each shard's shape, so all debris is still
  one draw call. On phones every shard collides as a box of the same volume
  (hulls cost them 20-30% more physics time); desktop browsers give hulls to
  the big chunks, native desktop to nearly all of them.
- Resting rubble is frozen into static bodies (piles used to stay awake
  forever), and thawed when anything disturbs it.
- Every kind of thing is one draw call: blocks, debris, chips, dust, rebar.
- Dust is a few large clouds drawn from one noise texture (overdraw is what
  hurts phones), lit and eroded in the shader.
- Phones get a lighter tier (render scale, shadow range, fewer pieces), and
  the adaptive quality steps down further if frames run long.
- Measure with `godot --headless --path . -- --mode=showcase --prof --seed=1`
  (add `--quality=low` for the phone settings). The physics time is the real
  mean and worst step of each second (`scripts/core/physics_clock.gd`), not
  the engine's monitor, which reports the worst frame of the last second.

## How it works

| Piece | File |
| --- | --- |
| The map (open in the editor; structures preview) | `levels/sandbox.tscn`, `scripts/game/level.gd`, `scripts/game/arena.gd` |
| The palace and the campanile: storeys, rusticated ground floor, window dressings, arcades and voussoirs, loggia, cornice, roof, tower with belfry and copper dome | `scripts/destruction/palazzo.gd`, `scripts/destruction/structure.gd` |
| The square: flagstones, travertine bands and kerbs, the plain beyond, the haze | `shaders/floor.gdshader`, `materials/environment.tres` |
| K.O. and respawn | `scripts/game/level_run.gd`, `scripts/game/game_state.gd` |
| Powers: tuning, cooldowns, aiming | `scripts/powers/power_defs.gd`, `scripts/powers/power_caster.gd` |
| Black hole / black ice shield | `scripts/powers/vortex.gd`, `ice_shield.gd` |
| Health and what hurts | `scripts/player/player.gd`, `scripts/powers/hazards.gd` |
| Menu (live attract-mode backdrop) | `scenes/menu.tscn`, `scripts/ui/main_menu.gd` |
| Structural physics: loads and shear, toppling (also above a cut course), creak-and-hold, floor-by-floor pancake collapses | `scripts/destruction/structure_set.gd`, `falling_cluster.gd`, `sphere_grid.gd`, `structure_mesh.gd` |
| Walls that crack open in place (cells cut in Blender) | `scripts/destruction/wall_cells.gd` |
| Loose pieces: pooled server bodies + one MultiMesh; resting rubble freezes into static bodies until disturbed | `scripts/destruction/debris_system.gd` |
| Shard library: how concrete, wood and metal break (cut in Blender) | `tools/make_shards.py`, `assets/shards/shards.json`, `scripts/destruction/shard_library.gd` |
| Box patterns (fallback, and materials without shards) | `scripts/destruction/fracture.gd` |
| Materials and finishes (stone, plaster, travertine, marble, brick, terracotta, shutters, verdigris, bronze): look, weight, strength, breakage; cracks from the hit point | `scripts/destruction/materials.gd`, `shaders/block.gdshader` |
| Surface textures baked in Blender: stone, brick, plaster, travertine, marble and roof tiles built from nodes and baked (Cycles) into seamless colour, relief, roughness and joint maps (`python3 tools/make_textures.py`) | `tools/make_textures.py`, `assets/textures/` |
| Gravel and glass shards without physics (one bounce, rest, fade) | `scripts/fx/chip_system.gd` |
| Dust clouds, rolling dust walls (one noise texture, one draw call) | `scripts/fx/dust_system.gd`, `shaders/dust.gdshader` |
| The black hole's cloud of grains (moved by the shader) | `scripts/fx/grain_cloud.gd`, `shaders/grain.gdshader` |
| Rebar left in broken concrete | `scripts/fx/rebar_system.gd` |
| Quality tiers and adaptive quality (render scale, shadows, pieces kept) | `scripts/core/quality.gd`, `scripts/core/adaptive_quality.gd` |
| Physics timing (mean and worst step per second) | `scripts/core/physics_clock.gd` |
| Shake, slow motion on big collapses | `scripts/fx/*`, `scripts/core/game_world.gd` |
| Sound effects (synthesised, regenerate with `python3 tools/make_sounds.py`) | `audio/*.wav`, `scripts/core/sfx.gd` |
| Music and the wind on the square (seamless loops, `python3 tools/make_music.py`) | `audio/*.ogg`, `scripts/core/sfx.gd` |

### Shards: cut once in Blender, reused forever

Breaking is never computed at runtime: `tools/make_shards.py` (Blender's
Python module, `pip install bpy`) cuts unit cubes into Voronoi cells once,
with rough fracture faces, and writes `assets/shards/shards.json`:

- **Concrete:** 2 to 6 chunky pieces (at most 3 on phones, 4 in browsers).
- **The cascade:** every concrete and wood shard is cut again into 3 to 5
  sub-shards that tile it exactly. When a piece breaks a second time (a
  hard landing, the black hole's grinding) it splits along cracks that were
  already inside it; after that, pieces crumble into gravel. The seeds of
  these cuts come from a Geometry Nodes group (Mesh to Volume, then
  Distribute Points in Volume), so they fill any closed shape. **Wood:** long splinters along the
  grain. **Metal:** a few torn lengths (bent a little in the shader).
- Every shard is resampled onto the same 152-vertex layout, so one mesh
  draws all of them: the shapes live in a small texture the block shader
  reads by vertex index. **All debris is still one draw call.**
- Each shard carries its volume (mass, piece counts) and a collision hull
  of at most 20 points. To break a block, a pattern is turned so its grain
  follows the block's long axis, stretched to the block, and its shards are
  spawned from the pool: a break is a lookup, never a mesh build.
- Shards too small to be worth a body become gravel chips.

Regenerate after changing the script (a few seconds, Blender 5.2's module):

```sh
pip install bpy && python3 tools/make_shards.py   # also writes art/shards_preview.glb
godot --headless --path . --import
```

### Structural physics

After anything changes, each structure is re-checked:

1. **Connected pieces.** A piece with no contact to the ground falls as one
   rigid body (a compound of its blocks) and breaks apart where it lands.
2. **Toppling.** If a grounded piece's centre of mass leaves the footprint it
   stands on, it tips over as one body. The same check runs at every course
   where blocks were cut out: a tower whose foot is half gone falls over
   from there.
3. **Loads.** Weight flows top-down from each block to the blocks it rests on,
   split by contact area. Capacities (in compression and in shear) are
   calibrated on the intact structure (safety factor 2.4 for stone and
   concrete, 2 for wood, 3 for metal), so a building stands
   until enough supports are lost; then the most overloaded blocks crush, a
   few per frame, and the collapse spreads floor by floor.
4. **Impacts.** A falling piece damages the blocks it hits (heavier hits
   harder), so towers can be toppled into each other.
5. **Coming loose.** A block bigger than 0.4 m³ (1 m³ on phones) cracks into
   shards as it comes away: a wall panel never tumbles off whole.
6. **Walls crack open in place.** A wall panel that breaks is replaced by the
   cells of a wall pattern cut in Blender (prisms through its thickness,
   seeded by a Geometry Nodes Poisson disk): the cells round the hit break
   out, the others stay up as blocks of their own, linked along the faces
   they share (areas from Blender) and to what the panel touched. Holes get
   ragged edges across the stone joints, and the wall can go on failing a
   cell at a time. The cells are drawn in the wall's own space, so plaster
   and courses run on across them (`scripts/destruction/wall_cells.gd`).

Blocks keep their damage between blasts (shown as cracks), which lowers
their capacity.

### Performance budget

- Pieces are raw `PhysicsServer3D` bodies (no nodes), created once and pooled.
- Budget: 1500 pieces on desktop, 900 in desktop browsers, 500 on phones.
  Above 80% the oldest resting pieces shrink away; on web, pieces also
  expire after 240 s.
- The palace and the tower start with about 1,730 blocks (static bodies,
  one MultiMesh per kind).
- Showcase (`--mode=showcase --prof --seed=1`, native build on a 4-core
  Linux VM), physics ms per step while things are moving: phone
  settings 3.1 mean (worst second 5.1–5.2), browser settings 4.5–4.7
  (7.4–8.9), desktop 7.6–7.7 (12.8–17.9).
- CI fails if the browser-settings showcase averages more than 12 ms per
  busy step (`tools/perf_gate.py`). `godot -- --mode=bench` still measures
  raw body counts by hand.

## Develop

```sh
tools/install_godot.sh                     # official 4.7.2 editor into ~/.godot-ci
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn   # tests
godot --headless --path . res://tests/test_runner.tscn -- --quality=low   # phone settings
pip install "gdtoolkit==4.5.0" && gdlint scripts tests && gdformat --check scripts tests
godot --path . -- --mode=showcase --shots=/tmp/shots     # scripted blasts + screenshots
```

Workflow: branch → pull request → CI (lint, headless tests at desktop and
phone settings, physics perf gate, exports, keyboard and touch probe in
headless Chromium) and a Vercel preview → merge.
