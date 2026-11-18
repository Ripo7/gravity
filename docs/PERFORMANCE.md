# Performance

What was measured, and how to measure it again.

```sh
# The brute breaks the column, a panel of the wall and two columns under
# the slab, without a screen: the cost of the physics.
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="\
s-3.5,0.05,-4.55,-3.5,1,-6;w0.3;h;w0.4;h;w0.4;h;w0.4;h;w4;\
s0,0.05,-6.3,0,1,-8;w0.5;h;w0.5;h;w0.5;h;w0.5;h;w4;\
s3.4,0.05,-4.4,3.4,1,-5.9;w0.4;h;w0.4;h;w0.4;h;w0.4;h;w3.5;\
s6.6,0.05,-4.4,6.6,1,-5.9;w0.4;h;w0.4;h;w0.4;h;w0.4;h;w10"
```

`--prof` prints the cost of the physics once a second and, at the end, how
the steps are spread (`STEPS`: median, 99%, slowest).

## On a phone: the measure

Open the preview with `?mode=mesure` at the end of its address, leave the
phone alone for a minute, and take a picture of the screen when it says it
is done. Nobody plays: the brute stands where it starts and the same thing
happens every time (`Director._measure`). Three stretches: the bench whole
(5 s); every piece broken, one every 0.6 s, and what comes down given 6 s;
the rubble at rest (5 s). For each, the frames a second over the stretch
and in its slowest second. Then all of it a second time: a phone changes
pace by itself, and only what the two rounds agree on counts.

## Measured

### On the phone

Read off the game's own counter by the owner (iPhone, Safari): on the
bare bench of step 1 (pull request #56), the brute alone on the ground,
49 to 56 frames a second. That is what every later number on that phone
starts from.

Not measured yet on a phone: the bench with concrete on it, standing or
broken. The measure above is there for that.

### Concrete

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), things falling at 0.3 of real gravity.

The run at the top of this page (four combinations: the column, the
middle panel, two columns under the slab, which comes down; 1741 steps),
three times: a physics step costs 0.12 to 0.13 ms at the median, 99% of
the steps are under 0.37 to 0.41 ms, the slowest takes 2.2 to 2.3 ms. At
the end 17 to 31 bodies lie loose, 19 at most having moved at once. (How
the slab ends is not the same every time: whole and leaning, or in its
nine blocks, with a column or two broken under it.)

The bench is 9 pieces cut into 43 blocks.

### The bare bench (step 1)

Same machine. Nothing is drawn differently on a phone: there are no
quality tiers.

With nothing on the bench but the brute, a run of 667 steps (it runs,
jumps, throws the four blows, kicks, sprints), three times: a physics
step cost 0.10 ms at the median, 99% of the steps were under 0.20 to
0.28 ms, the slowest took 1.6 to 2.3 ms. This is what the brute's body
and its animation tree cost, and the floor every later number starts
from.

The blows, the button pressed again every tenth of a second: they land
0.27, 0.72, 1.15 and 1.95 s after the first press, and carry the body
2.3 m in all; the kick lands 0.52 s after its press and carries it 0.7 m.
When it counts, the fist is 1.39 m out for the hook, 0.79 and 0.81 m for
the two swings, 1.04 m for the leap; the foot 0.95 m out and 1.14 m up.

What a browser downloads besides the engine (`index.pck`): 0.69 MB then,
for 2.56 MB in the version before (both exported here with the same
Godot); 0.72 MB with concrete. The engine itself (`index.wasm`, 39.5 MB
before compression) is the same.

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
  once**, before two cases are told apart: hence the measure at the top
  of this page, the same thing twice over, a minute in all.
