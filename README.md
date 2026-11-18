# Gravity: a giant brute, and what it breaks

A giant brute in a toy city that breaks, seen in third person. The game
is being rebuilt from its concept, one step at a time, in greybox:
[docs/CONCEPT.md](docs/CONCEPT.md) (in French) says what it is to be, and
comes before the code.

**Where it is now: step 1 of 7, the bare bench.** A bare ground and one
brute that walks, runs, sprints, jumps, throws a four-blow combination and
kicks. Nothing stands on the bench yet. What breaks comes next, one
material at a time, each on this bench and each tried on a phone before
the next: concrete, metal, wood, glass; then a house, an office and a
tower made of them; then the city, made up from a number as before.

Godot 4.7, GDScript, Jolt physics, Compatibility renderer (WebGL2), so it
can be played in Safari on an iPhone from each pull request's preview.

The version before this one (two brutes fighting in a city of boxes cut
into shards) is kept as it was on the branch
[`archive/v1`](../../tree/archive/v1); what it taught is at the end of
the concept. The project before that is on
[`archive/gravity`](../../tree/archive/gravity).

## Controls

| | Keyboard and mouse | Phone |
| --- | --- | --- |
| Move | WASD (by position, so ZQSD on AZERTY) / arrows | left stick: pushed a little, a walk; fully, a run |
| Sprint | shift | the stick held fully pushed for 0.8 s |
| Look | mouse | drag on the right half |
| Strike | left click or F | big red button |
| Kick | right click or E | orange button |
| Jump | space | small button |
| Put the bench back | R | "Reconstruire" |

The camera sits behind the character's left shoulder and turns about its
head; it comes closer when a wall is behind (and the character is not
drawn when the camera is right against its back). The character goes where
you push, seen from the camera, and turns to face where it goes.

The strike button throws a lunging hook; pressed again before it is over,
the next blow of the combination follows: a swing up from the right, one
back across from the left, then a leap that comes down fist first, then
round again. A blow is thrown where the stick pushes, or where the
character faces.

The line at the top left shows frames per second, the cost of one physics
step and which build this is (it ends with the commit).

## Run

```sh
godot --path .                                                # play
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn   # tests
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- --only=blows
pip install "gdtoolkit==4.5.0" && gdlint scripts tests && gdformat --check scripts tests
```

`tools/install_godot.sh` downloads the right Godot (and `--templates` the
export templates) into `~/.godot-ci`.

Scripted runs (`scripts/core/director.gd`), on desktop after `--`, in a
browser as `index.html?mode=...`:

```sh
# Run, jump, the combination, a kick, then a sprint to the right.
godot --path . -- --mode=play --steps="p0,-1,1.5;j;p0,-1,1;h;w0.5;h;w0.5;h;w0.5;h;w2.2;k;w1.5;p1,0,1.2,1"
# The same without a screen, with the cost of the physics.
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="p0,-1,2;j;w1;h;w1;k;w1"
# Just look, from somewhere at something.
godot --path . -- --mode=still --pos=3,0.05,4 --at=0,1,0 --wait=2
```

Add `--write-movie out.avi --fixed-fps 30` before `--path` to record a run.

## Checks

- `tests/`: a small headless runner; files `tests/test_*.gd`, methods
  `test_*` (they may `await`). They play the real scene: the bench (one
  brute, no sun shadow, a round shadow that stays on the ground); the
  character (where the camera sits and how it comes in at a wall, the
  character turning to where it goes, its planted foot not sliding from a
  slow walk to a sprint, jumps and landings, stepping onto what is low);
  the blows (the four in order then standing again, each one saying when
  it lands, how far, how hard and which way, the kick); the controls, keys
  and thumbs; and the cut of a box into shards (volumes, shared faces).
- `tools/web_probe.mjs`: loads the web export in headless Chromium, plays
  a scripted run and fails on any error (`npm install playwright`, then
  `node tools/web_probe.mjs build/web shot.png`). WebGL2 is stricter than
  desktop OpenGL: two bugs only showed there.
- `.github/workflows/ci.yml` runs lint, tests, the web export and the
  probe on every pull request. Vercel builds a preview of the web export
  for every push (`vercel.json`, `tools/vercel_build.sh`).

## More

- [docs/CONCEPT.md](docs/CONCEPT.md): what the game is to be, and the plan.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is laid out.
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md): what was measured, and how.
- [CONTRIBUTING.md](CONTRIBUTING.md): the way a change goes in.
- [CREDITS.md](CREDITS.md): where the assets come from and their terms.
