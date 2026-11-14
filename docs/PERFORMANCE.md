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

The showcase tour of the house (84 shots from 14 places, 1100 to 1250 of
the 1516 shards down, 900 to 1200 pieces and 150 to 560 moving at once),
8 seeds:

- a physics step costs 0.4 to 1.1 ms at the median, and 1.2 to 1.6 ms on
  average while things move;
- 99% of the steps are under 3.6 to 6.8 ms, the slowest takes 5.5 to
  10.7 ms.

The character: a whole frame (one physics step and one idle step, the
house standing, nothing drawn) takes 0.10 to 0.13 ms while it runs, and
0.09 ms with its animation tree switched off: blending the clips costs
about 0.02 to 0.04 ms a frame here. The planted foot slides 0.05 to
0.2 m/s between a slow walk and a run, 0.5 to 1 m/s at a sprint
(7.8 m/s). The other brute, a second body with its own tree, adds 0.03
to 0.05 ms to that frame.

The fight: the four punches of the combination land 0.13, 0.37, 0.78 and
1.05 s after the first press; the kick lands 0.42 s after the press. When
a punch counts, the wrist is 0.59 to 0.76 m ahead of the body and within
0.11 m of the line to the other brute. Thrown by the fourth punch from in
front of the house, the other brute goes through the front wall, the room
and the back wall and lands 10.4 m away, 53 shards knocked out on the
way; it is back on its feet 3.3 s after the blow. In the open a kick
sends it 14 m. A scripted fight of 30 s in which each brute goes
through the house once (69 shards down, 80 pieces moving at once) costs
0.2 ms a physics step at the median, 99% of the steps under 2.4 ms, the
slowest 3.7 to 7.5 ms (two seeds). The boxing library is
0.33 MB of text (0.2 MB more in the web export, 2.8 MB in all).

Not measured: a real phone. The line at the top left is there for that.
