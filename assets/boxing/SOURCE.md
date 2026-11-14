# Boxing moves

`boxing.tres` is a Godot animation library for the mannequin of
`assets/mannequin`: a guard, four punches, a duck and a kick. They are
motion capture of real people, cut out of two takes and put on the
mannequin's skeleton by `tools/mocap/build.py`.

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

| Clip | Take | Seconds of the take | What it is |
| --- | --- | --- | --- |
| `guard` | 13_17 (boxing) | 25.36 to 26.36 | the stance, bouncing: a loop |
| `jab` | 13_17 | 2.87 to 3.14 | left straight to the head |
| `cross` | 13_17 | 3.11 to 3.62 | right straight, right after the jab |
| `hook_l` | 13_17 | 20.24 to 20.57 | left, rising, to the body |
| `hook_r` | 13_17 | 20.52 to 21.01 | right, rising, to the chest |
| `duck` | 13_17 | 11.62 to 12.41 | down under a punch and back up |
| `kick` | 135_07 (mawashigeri) | 0.46 to 1.31 | roundhouse with the right leg |

The jab and the cross are one passage of the take cut in two, and so are
the two body punches: chained, they are what the boxer did.

## Making it again

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/una-dinosauria/cmu-mocap /tmp/cmu
git -C /tmp/cmu sparse-checkout set --no-cone /data/013/13_17.bvh /data/135/135_07.bvh
python3 tools/mocap/build.py /tmp/cmu/data        # needs numpy
```

It prints, for each clip, when its fist or foot gets there, how far it
reaches and how far the body walks; the same numbers are stored in the
clip (`metadata/hit`, `next`, `reach`, `power`) and read by
`scripts/player/character.gd`.
