# Fighting moves

`moves.tres` is a Godot animation library for the mannequin of
`assets/mannequin`: a stance, three blows, a kick and a duck. They are
motion capture of real people, cut out of five takes and put on the
mannequin's skeleton by `tools/mocap/build.py`. The takes were picked for
weight rather than for technique: the brutes are no boxers.

## Where the motion comes from

The CMU Graphics Lab Motion Capture Database, <http://mocap.cs.cmu.edu/>,
in the BVH conversion by Bruce Hahne (cgspeed.com, 2010 release), as
mirrored at <https://github.com/una-dinosauria/cmu-mocap> (commit
`09a07f5`).

> This data is free for use in research and commercial projects worldwide.
> [...] The data used in this project was obtained from mocap.cs.cmu.edu.
> The database was created with funding from NSF EIA-0196217.

(from mocap.cs.cmu.edu; the conversion adds no restriction of its own, see
`READMEFIRST.txt` in the mirror.)

| Clip | Take (as the database names it) | Seconds of the take | What it is in the game |
| --- | --- | --- | --- |
| `stance` | 137_41 (strong man wait) | 11.52 to 13.12 | standing ready, a loop |
| `haymaker` | 13_17 (boxing) | 1.71 to 2.46 | a long right, stepping in |
| `swing` | 124_07 (baseball swing) | 2.56 to 3.31 | both fists swung across, no bat |
| `smash` | 79_01 (chopping wood) | 2.26 to 3.21 | both fists brought down from overhead, no axe |
| `kick` | 135_04 (front kick) | 2.62 to 3.31 | straight ahead with the right leg, stepping in |
| `duck` | 13_17 (boxing) | 11.62 to 12.41 | down under a blow and back up |

What the tool does to a take besides putting it on the skeleton: it turns
it so that the blow goes straight ahead, gives the steps to the root bone
(the game moves the body by them), and retimes it so that a blow reads as
heavy: slow to come, sudden when it does. The wind-up and the recovery
take 1.2 to 1.5 times as long as performed, the last 0.12 s before the
blow lands take 0.65 of their time, and the 0.06 s after it 2.5 times
theirs (the pose is all but held). The three blows come from three
people: chained, one runs into the next by a blend.

## Making it again

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/una-dinosauria/cmu-mocap /tmp/cmu
git -C /tmp/cmu sparse-checkout set --no-cone /data/013/13_17.bvh /data/079/79_01.bvh \
  /data/124/124_07.bvh /data/135/135_04.bvh /data/137/137_41.bvh
python3 tools/mocap/build.py /tmp/cmu/data        # needs numpy
```

It prints, for each clip, when its fist or foot gets there, how far it
reaches and how far the body walks; the same numbers are stored in the
clip (`metadata/hit`, `next`, `reach`, `power`, `height`, `above`, and
`way_x`, `way_y`, `way_z`: which way the fist or foot is going when it
gets there) and read by `scripts/player/character.gd`.
