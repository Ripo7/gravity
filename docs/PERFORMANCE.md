# Performance

What was measured, and how to measure it again.

```sh
# The brute takes the bench apart, without a screen: the cost of the
# physics. M n: it keeps striking for n seconds, a step from each piece
# (its straights do not step in). In concrete the column, the wall, two
# columns under the slab; in metal the post, a sheet, two posts under
# the deck; in wood the post, the palisade, a post under the floor; in
# glass the three panes.
M() { python3 -c "print(';'.join(['h;w0.25']*round($1/0.25)))"; }
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="\
s1.5,0.05,-5.0,1.5,1,-6;$(M 6);w4;s-1.5,0.05,-5.0,-1.5,1,-6;$(M 5);w4;\
s4.5,0.05,-7.0,4.5,1,-8;$(M 9);w4;s-4.5,0.05,-7.0,-4.5,1,-8;$(M 4);w4;\
s7.4,0.05,-4.9,7.4,1,-5.9;$(M 6);w3.5;s10.6,0.05,-4.9,10.6,1,-5.9;$(M 6);w8;\
s-7.4,0.05,-4.9,-7.4,1,-5.9;$(M 5);w3;s-10.6,0.05,-4.9,-10.6,1,-5.9;$(M 5);w10;\
s0,0.05,-9.1,0,1,-10;$(M 1);w2;s0,0.05,-12.0,0,1,-13;$(M 4.5);w3;\
s-1.4,0.05,-16.6,-1.4,1,-17.6;$(M 1);w6;\
s0,0.05,7.1,0,1,8;$(M 1);w3;s1.2,0.05,7.1,1.2,1,8;$(M 1);w3;s-1.2,0.05,7.1,-1.2,1,8;$(M 1);w3"
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

### The office building

Same machine, same way (headless, 2 cores, `--fixed-fps 60`, real
gravity). The bench has 185 pieces, drawn as 1077 parts (114 and 907
before): the building is 71 pieces and 170 parts.

The run at the top of this page (it never goes near the building), three
times, turn about with the build before. This build: 0.10 to 0.13 ms at
the median, 99% of the steps under 0.51 to 0.58 ms, the slowest 2.3 to
5.6 ms; 85 to 87 loose bodies at the end. The build before: 0.12 to
0.14 ms, 99% under 0.48 to 0.56 ms, the slowest 3.1 to 7.7 ms (one step
over 6 ms in one run); 85 to 87 loose bodies. No difference that these
runs can show.

The building brought down, three times: blows at a pane of its front,
then at each of the three columns of its front for 3.5 s, then six
seconds for it to come down and lie.

```sh
M() { python3 -c "print(';'.join(['h;w0.25']*round($1/0.25)))"; }
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="\
s-6.02,0.05,2.67,-6.77,1,2.95;w0.4;$(M 1.5);w1.5;\
s-5.74,0.05,3.46,-6.30,1,3.66;w0.4;$(M 3.5);w1.5;\
s-6.31,0.05,1.88,-6.87,1,2.09;w0.4;$(M 3.5);w1.5;\
s-6.88,0.05,0.31,-7.45,1,0.52;w0.4;$(M 3.5);w6"
```

0.15 to 0.18 ms at the median, 99% of the steps under 0.99 to 1.33 ms,
the slowest 4.4 to 4.9 ms, none over 6 ms. In its worst second a step
takes 0.79 to 1.04 ms. Up to 78 to 96 loose bodies move at once; 105 to
112 lie there at the end; 121 or 122 of the 185 pieces stand.

Before `_let_go` was changed (docs/ARCHITECTURE.md, "An office
building", 6), the same run, three times, turn about with the three
above: the slowest step took 16.1 to 21.7 ms, and four steps of each run
took more than 6 ms (10.5 to 21.7 ms): steps in which a blow knocked
blocks out of the first slab or cut a column. The median was 0.12 to
0.22 ms and 99% of the steps were under 1.30 to 1.79 ms.

That change leaves what happens as it was. One series of blows (a hole
in the edge of the first slab, one in a low wall, the three front
columns; a post of the house, a post under its ridge; two columns under
the slab of the bench, a post under the deck, a post under the floor,
four holes in the wall), each build started with the same random
numbers: after each blow every piece and every block is in the same
state in both builds, with as many loose bodies; both come to rest
after the same 305 steps, with the same 204 loose bodies, and where
those lie adds up to the same point to a tenth of a millimetre.

`index.pck` is 0.66 MB, as before. Nothing was measured on the phone.
What the picture costs was not measured: nothing is drawn in these runs
(170 more parts are drawn than before).

### A building that stands turned

Same machine, same way (headless, 2 cores, `--fixed-fps 60`, real
gravity). The bench is the same 114 pieces and 907 parts; the house
stands 30 degrees askew.

The run at the top of this page (it never goes near the house), three
times, turn about with the build before. This build: 0.13 to 0.15 ms at
the median, 99% of the steps under 0.50 to 0.53 ms, the slowest 3.1 to
6.8 ms (one step over 6 ms in one run); 85 or 86 loose bodies at the
end. The build before: 0.13 to 0.14 ms, 99% under 0.43 to 0.52 ms, the
slowest 3.2 to 8.0 ms (one step over 6 ms in two runs); 85 to 87 loose
bodies. No difference that these runs can show.

The house taken apart, three times each, turn about with the build
before (the run under "The house"): the same blows from the same four
places round it, told where they are now that it is turned (to the
centimetre).

```sh
M() { python3 -c "print(';'.join(['h;w0.25']*round($1/0.25)))"; }
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="\
s5.65,0.05,4.34,7,1,2;w0.3;$(M 2);w3;s9.12,0.05,3.22,7,1,2;w0.3;$(M 6);w3;\
s4.18,0.05,0.89,6.78,1,2.39;w0.3;$(M 6);w3;s8.35,0.05,-0.34,7,1,2;w0.3;$(M 6);w4"
```

Askew: 0.22 ms at the median, 99% of the steps under 0.66 to 0.67 ms,
the slowest 2.4 to 6.9 ms (one step over 6 ms in one run); 59 to 67
loose bodies at the end, all asleep. Straight, the build before: 0.19 to
0.22 ms, 99% under 0.65 to 0.76 ms, the slowest 2.1 to 3.1 ms; 56 to 59
loose bodies, all asleep. In all six runs 90 of the 114 pieces stand at
the end.

Does what comes off a turned piece come to rest? A concrete wall holed
in three places (36 blows), four of them straight and four turned (137,
137, 150 and 210 degrees) in one run, 1800 steps, with three starts of
the random numbers. With the corners of a block kept as they stood in
the world, a block of the turned wall was still moving at the end in 6
of the 12 turned walls, and in none of the 12 straight ones: it lay 4 to
5 cm into the ground (the same block of a straight wall rests 2 cm into
it, which is what the engine allows) and rocked there, once a second.
With its corners kept as the piece is laid out (this build), four
starts: none of 16 turned, none of 16 straight. The same with a sheet, a
post and a deck brought down beside the wall, three starts: none of 12,
none of 12.

A deck 40 m from the middle of the bench, one of its piers gone: in the
build before it was tied to none of the three piers that stood (to none
at 120 m, to one at 15 m, to the three where the bench has it); in this
build to the three, straight or turned.

`index.pck` is 0.66 MB, as before. Nothing was measured on the phone.
What the picture costs was not measured: it is not drawn in these runs
(the same 907 parts are drawn).

### The house

Same machine, same way (headless, 2 cores, `--fixed-fps 60`, real
gravity). The bench has 114 pieces, drawn as 907 parts (44 and 597
before): the house is 70 pieces and 310 parts. (This page said 887 and
290: the build prints 907.)

What the 70 more standing cost when nothing touches them: the run at the
top of this page (it never goes near the house), three times, turn
about with the build before. This build: 0.14 to 0.16 ms at the median,
99% of the steps under 0.47 to 0.52 ms, the slowest 4.4 to 6.3 ms (one
step over 6 ms in one run); 85 or 86 loose bodies at the end. The build
before: 0.15 to 0.16 ms, 99% under 0.44 to 0.54 ms, the slowest 4.2 to
7.8 ms (one step over 6 ms in one run); 86 to 88 loose bodies. No
difference that these runs can show.

The house taken apart, three times: two seconds of blows at the middle
of a gable (the roof comes down), then six at the back wall, at the
porch and at the other gable (2170 steps):

```sh
M() { python3 -c "print(';'.join(['h;w0.25']*round($1/0.25)))"; }
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="\
s7,0.05,4.7,7,1,2;w0.3;$(M 2);w3;s9.45,0.05,2,7,1,2;w0.3;$(M 6);w3;\
s4,0.05,2.45,7,1,2.45;w0.3;$(M 6);w3;s7,0.05,-0.7,7,1,2;w0.3;$(M 6);w4"
```

A physics step cost 0.19 to 0.23 ms at the median, 99% of the steps were
under 0.62 to 0.69 ms, the slowest took 2.2 ms, none over 6 ms. At the
end 90 of the 114 pieces still stand (the feet of the walls, the corner
posts, the plates) and 57 to 60 loose bodies lie there, all asleep.

`index.pck` is 0.66 MB (0.65 before). What drawing 310 more parts costs
was not measured: the picture is not drawn in these runs. Nothing was
measured on the phone.

### Three blows, one button

Same machine, same way (headless, 2 cores, `--fixed-fps 60`, real
gravity). The kick is out; nothing else of the game changes but one
landing that was dropped and now counts (see ARCHITECTURE.md).

The run at the top of this page (it never kicked), three times: a
physics step cost 0.12 to 0.13 ms at the median, 99% of the steps were
under 0.45 to 0.48 ms, the slowest took 5.3 to 7.5 ms (one step over
6 ms in two of the three runs); 84 to 88 loose bodies at the end. The
build before (glass), three times the same morning: 0.14 ms, 99% under
0.39 to 0.46 ms, the slowest 2.5 to 4.9 ms, none over 6 ms; 84 to 87
loose bodies. The slowest steps fall in seconds where little moves
(7.5 ms with six loose bodies, all asleep), in the build before too
(3.2 ms with none), which points at the machine; three runs do not tell
whether the steps over 6 ms are the machine's as well.

What the fists do alone, measured in the tests: the straights land 1.4 m
up and the fist of the leap 1.9 m up; once the straights meet nothing,
the leap lands on what is left, about 0.9 m up. Thirteen blows at one
spot of the palisade and the brute walks through. Thirteen at one spot
of the wall leave a sill 0.8 m high (it got through with a jump, tried
once); 65 blows, at three spots side by side, and it walks through. Not
measured on the phone.

### Glass (step 5)

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), things falling at real gravity. Glitter is not in
the physics: what is measured here is that bursting a pane costs no
slow step.

The three panes alone (765 steps), five times: a physics step cost
0.10 to 0.12 ms at the median, 99% of the steps were under 0.25 to
0.34 ms, the slowest took 2.2 to 2.4 ms, none over 6 ms.

The run at the top of this page (the same as before, then the panes:
7225 steps), three times: 0.14 to 0.15 ms at the median, 99% under
0.44 to 0.45 ms, the slowest 2.5, 6.0 and 24.2 ms (one step over 6 ms
in two runs of three, not at the panes: this machine does that by
itself); 82 to 88 loose bodies at the end, 20 to 25 at most moving at
once.

Not measured: what drawing the glitter costs (up to 200 small quads a
pane for about 2.5 s, one draw call each pane), here or on a phone.

### The three blows (two straights and the leap)

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), things falling at real gravity.

The run this page has at the top changed with the blows (the brute now
stands a step from each piece, and strikes for other lengths of time:
6490 steps). Three times: a physics step cost 0.15 to 0.16 ms at the
median, 99% of the steps were under 0.47 to 0.57 ms, the slowest took
2.5 to 6.8 ms (a step over 6 ms in two runs of three, as this machine
does by itself); 85 to 86 loose bodies at the end, 20 to 21 at most
moving at once. Not the run of the sections below: the two cannot be
compared. Nothing in the physics changed.

How many blows it takes now, the brute a step away and striking without
a pause: a sheet lies down at the 4th; the wall keeps its first hole at
the 5th; a metal post lies down at the 6th; the concrete column is cut
at the 7th; a plank snaps at the first.

Not measured on a phone.

### Wood (step 4)

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), things falling at real gravity.

The bench is 41 pieces now (16 before): 25 in wood, cut into 166 lengths
(594 parts in all, 428 before). What the 25 more standing cost when
none of them is struck: the run this page had at the top before (5507
steps, concrete and metal only), three times each, one build after the
other: 0.15 to 0.16 ms a physics step at the median before, 0.16 ms
with the wood standing; 99% of the steps under 0.38 to 0.48 ms before,
0.39 to 0.47 ms now; the slowest 2.5 to 2.8 ms before, 2.9 to 5.8 ms
now. Not told apart.

The run this page had at the top then (the same, then the wood: 6586 steps),
three times: 0.16 ms at the median, 99% of the steps under 0.43 to
0.57 ms, the slowest 2.4 to 5.7 ms; 104 to 106 loose bodies at the end,
24 to 26 at most moving at once.

The wood alone (its three stops: 1109 steps), three times: 0.15 to
0.17 ms at the median, 99% under 0.55 to 0.61 ms, the slowest 2.1 to
3.0 ms; 36 loose bodies at the end (lengths, long pieces, a beam, eight
boards), 25 to 29 at most moving at once.

Not measured on a phone, where what counts is how many bodies move at
once and how many parts are drawn: wood adds to both.

### Blows that land where the fist goes in

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), things falling at real gravity.

What following the fist costs: 20 s of blows in the open, where nothing
breaks (1310 steps), three times each, one build after the other. With
the blow a line from the body to where the fist ends: a physics step
cost 0.07 to 0.13 ms at the median, 99% of the steps were under 0.19 to
0.45 ms, the slowest took 2.2 to 3.4 ms. With the fist followed step by
step (a ball moved, two lines along the arm, for the 6 steps a fist is
thrown): 0.10 to 0.11 ms, 0.31 to 0.37 ms, 2.3 to 3.7 ms. Not told
apart.

The run this page had at the top then (5507 steps), three times: a physics
step cost 0.14 to 0.15 ms at the median, 99% of the steps were under
0.41 to 0.52 ms, the slowest took 3.2 to 3.7 ms; 70 loose bodies at the
end, 22 to 24 at most moving at once. This is not the run of the table
below (3930 steps, a combination at each piece): the blows of a
combination no longer land on one place, so the brute strikes for longer
and more comes down (the wall opens in four places).

Not measured on a phone.

### The body held back from what stands

Same machine, same two runs, one build after the other. Blows in the
open (1310 steps), three times each: 0.07 to 0.15 ms at the median
before, 0.11 to 0.12 ms with the body held back; 99% of the steps under
0.42 to 0.48 ms before, 0.32 to 0.38 ms now; the slowest 2.3 to 3.9 ms
before, 2.3 to 3.2 ms now. The run of 5507 steps, five times
before and seven now: 0.14 to 0.16 ms at the median before, 0.15 to
0.17 ms now; 99% under 0.38 to 0.57 ms before, 0.39 to 0.56 ms now; the
slowest 2.5 to 6.2 ms before, 2.5 to 9.0 ms now (a step over 6 ms in one
run of five before, in two of seven now: this machine does that by
itself). Not told apart; at the median it may be 0.01 ms more. Without
the look first at whether anything stands within a lunge, it was 0.01
to 0.02 ms more at the median in both runs.

Not measured on a phone.

### Concrete and metal, where the blow lands (step 3)

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), things falling at 0.3 of real gravity (what they
fell at to begin with then) unless it says otherwise.

The run this page had at the top then (both sides of the bench taken
apart, one combination at each piece, two at the metal posts: 3930
steps), three times each, the same hour:

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
