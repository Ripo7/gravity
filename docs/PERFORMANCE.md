# Performance

What was measured, and how to measure it again. Nothing here was measured
on a real phone: the line at the top left of the game (frames per second,
cost of a physics step, pieces) is there for that.

```sh
# The physics of a fixed tour that takes the house apart, at phone settings.
godot --headless --fixed-fps 60 --path . -- --mode=showcase --seed=1 --prof --quality=low \
  | python3 tools/perf_gate.py
```

`--prof` prints the cost of the physics once a second and, at the end, how
the steps are spread (`STEPS`: median, 99%, slowest). CI runs the tour on
every pull request and fails above 8 ms a step on average
(`tools/perf_gate.py`); the gate is loose on purpose, it catches a
regression, not 10%.

## Measured

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

The fight: the three blows of the combination land 0.30, 1.17 and 2.25 s
after the first press (each holds both brutes 0.07 s, 0.12 s for the
third); the kick lands 0.52 s after the press. When a blow counts, the
wrist is 0.22 to 0.29 m from the axis of the other brute. Who takes the
first blow slides 0.58 m. In the open a kick sends the other 11 m; it is
back on its feet 3.5 s after a throw. From behind the house the other
brute reaches the player in front of it in 4.9 to 8.4 s, 25 to 37 shards
knocked out on the way (3 seeds).

Locked on: from 10 m in the open, a blow lands 1.5 s after the press.
From 7.8 m with a wall in between, it lands 2.2 to 3.7 s after the press
(15 runs; it landed in all of them). The two brutes are seen 0.17 rad
apart at arm's length and 0.37 rad at 3 m (0.04 and 0.08 with the camera
straight behind the character).

A scripted fight of 27 s as played (the other brute attacking, the player
locked on, three combinations and three kicks) costs 0.2 ms a physics
step at the median, 99% of the steps under 1.2 ms, the slowest 2.2 to
2.9 ms (2 runs). Less of the house comes down in it than it used to: the
second blow now pushes the other brute aside before the third throws it,
and it no longer flies straight at the front wall. (Before that, 5 runs:
99% under 2.2 to 5.9 ms, slowest 4.9 to 9.1 ms and once 21.9 ms.) The
move library is 0.44 MB of text; the web export's data file is 2.3 MB.

Not measured: a real phone. The line at the top left is there for that.
