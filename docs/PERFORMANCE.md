# Performance

What was measured, and how to measure it again. Nothing here was measured
on a real phone: the line at the top left of the game (frames per second,
cost of a physics step, pieces) is there for that.

```sh
# The physics of a fixed tour that takes the city apart, at phone settings
# (add --level=house for the house).
godot --headless --fixed-fps 60 --path . -- --mode=showcase --seed=1 --prof --quality=low \
  | python3 tools/perf_gate.py
```

`--prof` prints the cost of the physics once a second and, at the end, how
the steps are spread (`STEPS`: median, 99%, slowest). CI runs the tour on
every pull request and fails above 8 ms a step on average
(`tools/perf_gate.py`); the gate is loose on purpose, it catches a
regression, not 10%.

## Measured

### On the phone

The first numbers from the phone itself, read off the game's own counter
in a screen recording by the owner (iPhone, Safari, city 67414, build
6062656, 52 s of fighting): 30 to 40 frames a second, with the physics at
0.6 to 2.0 ms a step and 19 to 353 pieces. So it is the picture that
costs there, not the breaking (recording the screen costs some of it
too). A first round of `?mode=bench&city=49` on that phone (1758 x 720, the
same view drawn six ways, 3 s each): as played 32 frames a second;
without shadows 45; walls without their dress 32; without both 47; at
half the resolution 45; without the city 28. So the walls' dress costs
nothing that shows, the city itself is not what is slow, and either the
shadows or the number of pixels is worth about 9 ms a frame, which points
at what is done per pixel: reading the shadow (four maps, blurred) and
smoothing the edges (MSAA 2x), neither of which the phone tier lowers
today. Even with shadows and dress off it stays under 50. The bench now
draws seven other ways to tell these apart: simple shadows (one map, not
blurred), no smoothing, both, then without the brutes, then without
shadows or city, then as played again (to see whether the phone slowed
down meanwhile).

The second round, same phone and view: as played 48; simple shadows 37;
no smoothing 29; both 37; both without the brutes 33; without shadows or
city either 60; as played again 29. The same settings gave 48 at the
start and 29 half a minute later, so the differences between the cases
in between mean nothing: three seconds a case on a phone that changes
pace by itself cannot tell them apart. What both rounds do agree on:
with no shadows the phone is at its fastest (45 and 47 with the city, 60
with next to nothing to draw), and it can reach 60.

So the game does not rely on a setting chosen by guess: it keeps pace by
itself (`Main.keep_pace`). When it is drawn at fewer than 40 frames a
second over 3 s, twice running, it gives up the sun's shadows (the
brutes keep a round one at their feet), and if that is not enough, a
quarter of the resolution; never more, and it does not take them back.
The counter then shows "allege 1" or "allege 2". Scripted runs are left
alone.

### The city (default level)

Same machine and settings. Cities are made up from a number and are not
all as big: of numbers 0 to 59, the lightest is planned at 844 shards and
the heaviest at 1889 (the cap is 1900); forty of them built one after the
other are 830 to 1931 shards, all stand as built (no bond above 0.26 of
what breaks it) and the slowest is cut and bonded in 0.39 s headless.

The showcase tour (84 blows from 14 places: every tower, then the offices
and houses nearest the square, each from the nearest kerb), on cities 1,
4, 19, 37 and 49 (1282 to 1975 shards, the last three among the
heaviest): 0.7 to 1.0 ms a step on average while things move (the house:
1.8 to 2.0), the worst second 1.5 to 2.0 ms, the slowest step 4.4 to 6.0
ms, at most 471 to 595 pieces. A 40 s fight on the square of city 49 (the
other brute attacking): 0.7 ms in the worst second, 0.16 at the median.
CI runs the tour on city 49.

The ground (`shaders/ground.gdshader`) is worked out for each pixel
instead of being one flat colour. Where every pixel is computed on the
processor (software rendering, 1280 x 720, city 29, the first three cases
of `--mode=bench`, three runs each): 3.6 to 3.7, 5.8 to 6.0 and 6.5 to 6.8
frames a second before; 3.4 to 3.6, 5.7 to 5.8 and 6.4 to 6.6 after. So
0 to 5 % of the picture there; not measured on the phone.

A face of a box is drawn as a fan round its middle (for the scars of a
shard that has taken blows): one vertex more a face. City 49 goes from
114 501 to 119 529 vertices (4 %), cut and built in 0.56 to 0.70 s
instead of 0.54 to 0.64 (three runs each, headless).

### The house

Headless on a 2-core cloud machine, one physics step per frame
(`--fixed-fps 60`), phone settings.

The showcase tour of the house (84 blows from 14 places, 1150 to 1220 of
the 1516 shards down, 1060 to 1260 pieces and 310 to 520 moving at once),
5 seeds:

- a physics step costs 0.6 to 0.8 ms at the median, and 1.9 to 2.5 ms on
  average while things move;
- 99% of the steps are under 6.1 to 8.3 ms, the slowest takes 10.6 to
  16.3 ms.

The tour used to shoot a ball; it now lands a brute's blow where the
camera looks. A blow arrives at once and loose pieces on the way do not
stop it, so more comes down at a time and the two tours are not the same
load: the day the ball was removed, on the same machine, the tour with the
ball cost 1.3 to 1.9 ms on average while things move, 99% of the steps
under 4.7 to 6.9 ms, the slowest 8.5 to 10.8 ms (3 seeds).

The character: a whole frame (one physics step and one idle step, the
house standing, nothing drawn) takes 0.10 to 0.13 ms while it runs, and
0.09 ms with its animation tree switched off: blending the clips costs
about 0.02 to 0.04 ms a frame here. The planted foot slides 0.05 to
0.2 m/s between a slow walk and a run, 0.5 to 1 m/s at a sprint
(7.8 m/s). The other brute, a second body with its own tree, adds 0.03
to 0.05 ms to that frame.

The fight: the four blows of the combination land 0.28, 0.82, 1.33 and
2.22 s after the first press (each holds both brutes 0.07 s, 0.12 s for
the last); the kick lands 0.53 s after the press. When a blow counts, the
wrist is 0.22 to 0.24 m from the axis of the other brute, for all four.
Who takes the first blow slides 0.58 m. Thrown by the fourth from in
front of the house, the other brute goes through the front wall, the
room and the back wall and lands 10.4 m away, 64 shards knocked out on
the way; it is back on its feet 3.3 s after the blow. In the open a kick
sends it 11 m. From behind the house the other brute reaches the player
in front of it in 6.3 to 9.1 s, 34 to 37 shards knocked out on the way
(3 seeds).

Locked on: from 10 m in the open, a blow lands 1.4 s after the press.
From 7.8 m with a wall in between, it lands 1.8 to 2.5 s after the press
(11 runs; it landed in all of them). The two brutes are seen 0.17 rad
apart at arm's length and 0.37 rad at 3 m (0.04 and 0.08 with the camera
straight behind the character).

The guard, held for 15 s against the other brute: 10 blows met it, none
got through (not a flinch, not a throw), 0.8 m of ground given in all.

A scripted fight of 26 s as played (the other brute attacking, the player
locked on: two combinations, the guard held twice, two kicks) costs
0.2 ms a physics step at the median, 99% of the steps under 1.4 ms, the
slowest 3.0 ms (1 run). The move library is 0.55 MB of text (the clips made for games
move every finger); the web export's data file is 2.3 MB.

Not measured: a real phone. The line at the top left is there for that.
