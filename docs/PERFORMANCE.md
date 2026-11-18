# Performance

What was measured, and how to measure it again. The bench of this version
has not been measured on a phone yet: the line at the top left of the game
(frames per second, cost of a physics step) is there for that.

```sh
# A scripted run on the bench, with the cost of the physics.
godot --headless --fixed-fps 60 --path . -- --mode=play --prof \
  --steps="p0,-1,2;j;p0,-1,1;h;w0.5;h;w0.5;h;w0.5;h;w2.5;k;w1.5;p1,0,2,1"
```

`--prof` prints the cost of the physics once a second and, at the end, how
the steps are spread (`STEPS`: median, 99%, slowest).

## Measured

### The bare bench

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`). Nothing is drawn differently on a phone yet: there are
no quality tiers.

The run above (the brute runs, jumps, throws the four blows, kicks,
sprints: 667 steps), three times: a physics step costs 0.10 ms at the
median, 99% of the steps are under 0.20 to 0.28 ms, the slowest takes 1.6
to 2.3 ms. There is nothing on the bench but the brute: this is what its
body and its animation tree cost, and the floor every later number starts
from.

The blows, the button pressed again every tenth of a second: they land
0.27, 0.72, 1.15 and 1.95 s after the first press, and carry the body
2.3 m in all; the kick lands 0.52 s after its press and carries it 0.7 m.
When it counts, the fist is 1.39 m out for the hook, 0.79 and 0.81 m for
the two swings, 1.04 m for the leap; the foot 0.95 m out and 1.14 m up.

What a browser downloads besides the engine (`index.pck`): 0.69 MB, for
2.56 MB in the version before (both exported here with the same Godot).
The engine itself (`index.wasm`, 39.5 MB before compression) is the same.

Not measured: a real phone.

### What the version before measured on the phone

Kept because it decides how this version is drawn. The numbers are of the
city of boxes on the branch `archive/v1`, read off the game's own counter
by the owner (iPhone, Safari).

- As played (52 s of fighting, city 67414): 30 to 40 frames a second, with
  the physics at 0.6 to 2.0 ms a step and 19 to 353 pieces. So it was the
  picture that cost there, not the breaking.
- The same view drawn several ways, 3 s each, two rounds: without the
  sun's shadows the phone was at its fastest (45 and 47 frames a second
  with the city, 60 with next to nothing to draw); the walls' dress cost
  nothing that showed; hiding the city did not help.
- In the second round the same settings gave 48 frames a second at the
  start and 29 half a minute later: three seconds a case, on a phone that
  changes pace by itself, cannot tell two cases apart.

What this version takes from it:

- **The sun casts no shadow, from the start.** The brute has a round one
  on the ground.
- **The picture no longer gives anything up by itself.** The version
  before dropped the shadows, then a quarter of the resolution, when it
  ran slow. With the shadows gone there is nothing left to drop first,
  and a build that changes how it draws while it is being measured cannot
  be compared with another.
- **A measurement on the phone has to last, and to be made more than
  once**, before two cases are told apart. The bench has no measuring
  mode yet: there is nothing to compare. One comes with the first
  material.
