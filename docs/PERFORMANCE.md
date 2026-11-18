# Performance

What was measured, and how to measure it again.

```sh
# The brute takes both sides of the bench apart, without a screen: the
# cost of the physics. C: a combination; in concrete the column, a place
# of the wall, two columns under the slab; in metal the post, a sheet, two
# posts under the deck (two combinations each for the posts).
C="w0.4;h;w0.4;h;w0.4;h;w0.4;h"
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="\
s1.5,0.05,-4.55,1.5,1,-6;$C;w4;s-1.5,0.05,-4.6,-1.5,1,-6;$C;w2;$C;w4;\
s4.5,0.05,-6.3,4.5,1,-8;$C;w4;s-4.5,0.05,-6.4,-4.5,1,-8;$C;w4;\
s7.4,0.05,-4.4,7.4,1,-5.9;$C;w3.5;s10.6,0.05,-4.4,10.6,1,-5.9;$C;w8;\
s-7.4,0.05,-4.5,-7.4,1,-5.9;$C;w2;$C;w3;s-10.6,0.05,-4.5,-10.6,1,-5.9;$C;w2;$C;w10"
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

Since then, on that phone, with concrete and metal on the bench: 48 to
53 frames a second while it is broken (see below). The measure above is
still the way to compare two builds.

### Concrete and metal, where the blow lands (step 3)

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), things falling at 0.3 of real gravity (what they
fell at to begin with then) unless it says otherwise.

The run at the top of this page (both sides of the bench taken apart:
3930 steps), three times each, the same hour:

| | median | 99% of the steps under | slowest |
| --- | --- | --- | --- |
| metal bent as a whole piece, the deck one rigid body | 0.13 to 0.18 ms | 0.39 to 0.60 ms | 3.0 to 4.6 ms |
| metal marked where the blow lands (dents, kinks, folds, the deck in triangles) | 0.14 ms | 0.35 to 0.46 ms | 2.2 to 8.3 ms |
| the same again, later | 0.14 to 0.16 ms | 0.35 to 0.44 ms | 2.4 to 4.2 ms |
| and concrete broken where the blow lands (holes, what holds over them) | 0.13 to 0.16 ms | 0.34 to 0.58 ms | 3.2 to 11.8 ms |
| walls and columns cut finer (blocks 0.4 m across: a hole round the fist) | 0.13 to 0.15 ms | 0.34 to 0.48 ms | 2.5 to 3.3 ms |
| the same, things falling at real gravity (1.0) | 0.14 ms | 0.35 to 0.40 ms | 2.4 to 2.9 ms |

The rows cannot be told apart at the median on this machine. The slowest
step is not better, and once in three runs it was worse (8.3 ms, 11.8 ms;
24 ms once with the finer cut, before a wall that loses blocks stopped
being made again whole).
In a run of 1000 steps made three times with the clock on every step, the
slowest steps (2 to 8 ms) were not the ones in which a hole was knocked,
a slab came down or the deck came loose: on this machine they come from
elsewhere. That is not a measure of a phone.

At the end of the run 25 to 41 bodies lie loose, 21 at most having moved
at once; 48 to 50 with the finer cut, 22 at most at once.

The first hole knocked in the wall costs 2.2 to 3.1 ms by itself in the
step it happens in (timed three times): the wall stops being one box and
becomes its 54 blocks, less those knocked out. The next ones cost 0.4 to
0.7 ms.

Not measured: what a fold costs on a phone. A piece of metal that has
come loose is up to 8 bodies and as many folds while it moves (the deck),
frozen like the rest once it lies still.

The bench is 16 pieces: 7 in concrete, cut into 100 blocks (6 for the
column, 54 for the wall, 6 for each column under the slab, 16 for the
slab), and 9 in metal, drawn with 46 rings (the posts) and 282 nodes
(the sheets, the deck): 428 parts.

On the owner's phone (iPhone, Safari), read off a screen recording of 38
s of play on the build before the finer cut (47 blocks), things falling
at real gravity: 48 to 53 frames a second from start to end, 51 while
the slab broke up (28 loose bodies, 20 moving), 51 with 39 lying at the
end; the physics 0.4 to 1.0 ms a step. Recording the screen costs
something too. Not measured on the phone: the finer cut.

### Concrete alone (step 2)

Same machine, with only the concrete on the bench: four combinations
(the column, the middle panel, two columns under the slab, which comes
down; 1741 steps), three times: a physics step cost 0.12 to 0.13 ms at
the median, 99% of the steps were under 0.37 to 0.41 ms, the slowest
took 2.2 to 2.3 ms; 17 to 31 loose bodies at the end, 19 at most moving
at once.

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
Godot); 0.72 MB with concrete, 0.74 MB with metal too, 0.75 MB with
both broken where the blow lands. The engine itself
(`index.wasm`, 39.5 MB before compression) is the same.

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
