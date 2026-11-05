# Gravity

First-person destruction game in Godot 4.7 (GDScript, Jolt physics).
You have overpowered powers. Flatten each map as fast as you can, without
getting crushed by what you bring down.

One sandbox map: a dense city district you stand inside. Streets and alleys
between closed multi-storey buildings you can walk into, switchback ramps in
the alleys, walkways across the avenue and over the boulevard, water towers
on the roofs; the rest of the city fades into the haze around it.

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
respawn at the start; the HUD counts destruction and K.O.s.

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
  chips with no collision (an arc, one bounce on the surface below, rest).
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
- Measure with `godot --headless --path . -- --mode=showcase --prof --seed=7`
  (add `--quality=low` for the phone settings).

## How it works

| Piece | File |
| --- | --- |
| Sandbox map (open in the editor; structures preview) | `levels/sandbox.tscn`, `scripts/game/level.gd`, `scripts/destruction/structure.gd` |
| Sandbox flow, K.O. and respawn, callouts | `scripts/game/level_run.gd`, `scripts/game/game_state.gd` |
| Powers: tuning, cooldowns, aiming | `scripts/powers/power_defs.gd`, `scripts/powers/power_caster.gd` |
| Black hole / black ice shield | `scripts/powers/vortex.gd`, `ice_shield.gd` |
| Health and what hurts | `scripts/player/player.gd`, `scripts/powers/hazards.gd` |
| Menu (live attract-mode backdrop) | `scenes/menu.tscn`, `scripts/ui/main_menu.gd` |
| Structural physics: health, loads, toppling, creak-and-hold, floor-by-floor pancake collapses, roof structures tied to what they stand on | `scripts/destruction/structure_set.gd` |
| Loose pieces: pooled server bodies + one MultiMesh; resting rubble freezes into static bodies until disturbed | `scripts/destruction/debris_system.gd` |
| Shard library: how concrete, wood and metal break (cut in Blender) | `tools/make_shards.py`, `assets/shards/shards.json`, `scripts/destruction/shard_library.gd` |
| Box patterns (fallback, and materials without shards) | `scripts/destruction/fracture.gd` |
| Concrete / wood / metal / glass: look, weight, strength, breakage; irregular chunks cut in the vertex shader; cracks from the hit point; weathering | `scripts/destruction/materials.gd`, `shaders/block.gdshader` |
| Gravel and glass shards without physics (one bounce, rest, fade) | `scripts/fx/chip_system.gd` |
| Dust clouds, rolling dust walls, haze, trails (one noise texture, one draw call) | `scripts/fx/dust_system.gd`, `shaders/dust.gdshader` |
| Rebar left in broken concrete | `scripts/fx/rebar_system.gd` |
| Quality tiers and adaptive quality (render scale, shadows, pieces kept) | `scripts/core/quality.gd`, `scripts/core/adaptive_quality.gd` |
| Shake, slow motion on big collapses | `scripts/fx/*`, `scripts/core/game_world.gd` |
| Sound effects (synthesised, regenerate with `python3 tools/make_sounds.py`) | `audio/*.wav`, `scripts/core/sfx.gd` |
| Music, city ambience, distant sirens, wing claps (synthesised, `python3 tools/make_music.py`) | `audio/*.ogg`, `scripts/core/sfx.gd` |
| Birds: pigeons on the roofs that flee from destruction, gulls circling (one draw call, no physics) | `scripts/fx/bird_system.gd`, `shaders/bird.gdshader` |
| The printed city: building styles (Roman, medieval, Renaissance), finishes (ashlar, brick, printed travertine and marble, plaster, tiles, composite) carried by every piece, the honeycomb inside printed stone, lit windows, the skyline | `scripts/destruction/structure.gd`, `scripts/destruction/materials.gd`, `shaders/block.gdshader`, `shaders/skyline.gdshader` |
| The colossal city around the district (temple towers, aqueduct, guardians, chimneys; scenery, one draw call per piece) and the street decor (lamps, braziers, standards, statues, pipes), modelled in Blender: `python3 tools/make_megacity.py` | `tools/make_megacity.py`, `assets/megacity/kit.glb`, `scripts/game/megacity.gd`, `scripts/game/street_decor.gd` |
| One of every building, to look at: `godot --path . -- --level=res://levels/showroom.tscn` | `levels/showroom.tscn` |

### Shards: cut once in Blender, reused forever

Breaking is never computed at runtime: `tools/make_shards.py` (Blender's
Python module, `pip install bpy`) cuts unit cubes into Voronoi cells once,
with rough fracture faces, and writes `assets/shards/shards.json`:

- **Concrete:** 2 to 10 chunky pieces. **Wood:** long splinters along the
  grain. **Metal:** a few torn lengths (bent a little in the shader).
- Every shard is resampled onto the same 152-vertex layout, so one mesh
  draws all of them: the shapes live in a small texture the block shader
  reads by vertex index. **All debris is still one draw call.**
- Each shard carries its volume (mass, piece counts) and a collision hull
  of at most 20 points. To break a block, a pattern is turned so its grain
  follows the block's long axis, stretched to the block, and its shards are
  spawned from the pool: a break is a lookup, never a mesh build.
- Shards too small to be worth a body become gravel chips.

Regenerate after changing the script (about a second):

```sh
pip install bpy && python3 tools/make_shards.py   # also writes art/shards_preview.glb
godot --headless --path . --import
```

Measured on the showcase (`--prof --seed=7`, physics ms per frame, same
machine): phone settings 6.2-6.8 with shards vs 5.6-5.8 with the old boxes;
desktop with hulls 8.3-11.2 vs 6.5-6.9. Resting rubble now freezes faster
and fast pieces only plough through rubble when they are big enough, which
paid for most of it.

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
- Budget: 1500 pieces on desktop, 900 in desktop browsers, 700 on phones.
  Above 80% the oldest resting pieces shrink away; on web, pieces also
  expire after 240 s.
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
