# Concept: two brutes in a house that breaks

Two fighters, stronger than people are, in a greybox scene where what
stands can be broken: a hard blow sends the other one through the walls.
Seen in third person.

- **Destruction.** Walls break into irregular shards where they are hit, and
  into smaller crumbs where they are hit hardest; what is no longer held up
  falls, and breaks again when it lands. Nothing disappears: the rubble
  stays and you can climb on it. Fists, feet and flying bodies break it.
- **Character animation.** A mannequin that stands, walks, jogs, sprints,
  jumps and lands by blending ready-made clips; and that fights with
  animations made for games, big and quick: a lunging hook, a swing up, one
  back across, a leap that ends fist first on the ground. Thrown, it goes
  over backwards onto its back and gets up. Holding the guard, it puts
  both fists up and nothing else. (The kick is still motion capture.)
- **The fight.** The other brute, in red, walks up to you and throws the
  same moves. The leap and the kick send whoever takes them flying,
  through anything that stands in the way.
- **Locking on.** Locked on the other brute, the camera stays on it and a
  blow asked for from too far runs at it first, through a wall if there is
  one, so that it lands instead of being thrown at nothing.

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
| Strike | left click or F | big red button |
| Kick | right click or E | orange button |
| Guard (hold) | C or ctrl | white button |
| Lock on / let go | middle click or tab | the sight |
| Jump | space | small button |
| Rebuild the house | R | "Reconstruire" |

The camera sits behind the character's left shoulder and turns about its
head; it comes closer when a wall is behind (and the character is not
drawn when the camera is right against its back). The character goes where
you push, seen from the camera, and turns to face where it goes.

The strike button throws a lunging hook; pressed again before it is over,
the next blow of the combination follows: a swing up from the right, one
back across from the left, then a leap that comes down fist first, then
round again. The leap and the kick throw the other brute; it throws you
the same way.

The guard is held: both fists come up in front of the face and stay there
for as long as the button is down, feet still, turned to the other brute
when locked on. Whatever comes from in front then stops on it: no flinch,
no throw, a little ground given. From behind it is no use. A strike can
be thrown from it, and it comes back after the strike if it is still
held.

A blow that lands stops both brutes for an instant and shakes the camera;
who takes it leans and slides the way the fist goes.

The fight starts locked on the other brute: an orange ring marks it, the
camera follows it from a little to the side, so that the two are seen
side by side, and looking around waits. A strike then always goes to
it: from too far, the character sprints at it first and strikes on
arrival, going through what stands in between. The sight lets go (and
locks on again); dodging or jumping calls a run off.

The line at the top left shows frames per second, the cost of one physics
step and how many pieces there are (and how many are moving).

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
# Your own steps: look there, a blow where you look, wait, run forward...
godot --path . -- --mode=play --from=-2.5,0.05,4.2 --steps="a@-2.5,1.4,-0.6;o;w1;o@-2,2,-0.6;w2;f0.8"
# The character on open ground: walk, run, sprint to the right, jump.
godot --path . -- --mode=play --from=-25,0.05,30 --steps="p0.2,0,2;p1,0,2;p1,0,2,1;j;w1.5"
# Lock on, the combination from afar (it runs in, the third blow sends the
# other through the house), then a kick: it goes in after it.
godot --path . -- --mode=play --from=4,0.05,15 --steps="l;w0.8;h;w1.5;h;w0.6;h;w0.6;h;w5;k;w4"
# As played: the other brute attacks, the player is locked on it.
godot --path . -- --mode=play --fight --from=4,0.05,15 --steps="w1;h;w0.5;h;w0.5;h;w4;k;w3"
# How loaded the house is as built (1 = a bond breaks).
godot --headless --path . -- --mode=check
```

Add `--write-movie out.avi --fixed-fps 30` before `--path` to record a run.

## Checks

- `tests/`: a small headless runner; files `tests/test_*.gd`, methods
  `test_*` (they may `await`). They cover the cut (volumes, shared faces),
  what holds and what falls, blows at the house, the controls, and the
  character: where the camera sits and how it comes in at walls, the
  character turning to where it goes, its planted foot not sliding from a
  slow walk to a sprint, jumps and landings, and the fight: the four
  blows in order then standing again, the step in and the fist being on the
  other brute when the blow counts, what is out of reach, the blow from
  overhead throwing it through the house, the kick, fists breaking a
  wall, the other brute coming through the house to hit back and throwing
  the player; the guard held, stopping what comes from in front and not
  what comes from behind; a blow that lands holding both for an instant and
  shaking the camera, who takes it going the way it goes; and locking on:
  the camera showing the two side by side, a blow from afar running in
  and landing, through a wall too.
- `tools/perf_gate.py`: reads a profiled showcase and fails when the
  physics gets too slow.
- `tools/web_probe.mjs`: loads the web export in headless Chromium, breaks
  the house and fails on any error (`npm install playwright`, then
  `node tools/web_probe.mjs build/web shot.png`). WebGL2 is stricter than
  desktop OpenGL: two bugs only showed there.
- `.github/workflows/ci.yml` runs lint, tests, the perf gate, the web
  export and the probe on every pull request. Vercel builds a preview of
  the web export for every push (`vercel.json`, `tools/vercel_build.sh`).

## More

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is laid out,
  how the destruction and the fight work.
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md): what was measured, and how.
- [CONTRIBUTING.md](CONTRIBUTING.md): the way a change goes in.
- [CREDITS.md](CREDITS.md): where the assets come from and their terms.
