# Fighting moves

`moves.tres` is a Godot animation library for the mannequin of
`assets/mannequin`, built by `tools/moves/build.py` from two sources:
animations made for games, and motion capture for what those do not have.

## Made for games: Universal Animation Library 2

By **Quaternius** (<https://quaternius.com/packs/universalanimationlibrary2.html>),
the author of the mannequin. Licence: **CC0 1.0** (public domain). Its
skeleton is the mannequin's own, bone for bone and at rest, under other
names, so the clips are taken over as they are: nothing is retargeted.

Only the free "Standard" version is used (43 clips; the paid "Source"
version has 134). The files, `UAL2_Standard.glb` and `UAL2_Standard_RM.glb`
(the same clips, with the steps on the root bone), were taken from the
mirror <https://github.com/NafisRayan/Animate-Rigged-Humanoid-No-Blender>
(commit `5821923`, 2026-09-18), which holds the pack as unzipped:

    8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8  UAL2_Standard.glb
    814eee878f82934992d3ea746c539df25e981487109c591f5efbb8dd03286f99  UAL2_Standard_RM.glb

| Clip | Made of | What it is in the game |
| --- | --- | --- |
| `hook` | `Melee_Hook`, then `Melee_Hook_Rec` | a lunging hook, the body dropping into it |
| `upswing` | `Sword_Regular_A`, then `Sword_Regular_A_Rec` | dashing in, a swing from low on the right to high on the left |
| `backhand` | `Sword_Regular_B`, then `Sword_Regular_B_Rec` | back across, from the left to the right |
| `slam` | `Sword_Heavy_Combo`, 2.1 to 3.8 s | a leap, the fist straight up, and down to the ground |
| `thrown` | `Hit_Knockback` | off its feet, over backwards, onto its back |
| `getup` | `LayToIdle` | from lying on its back to standing |

The free version has one blow made as a punch (the hook). The three others
are sword strokes thrown without the sword: the first two of the regular
combination, and the last of the heavy one, cut out of the clip of the
whole combination. Each `_Rec` is the recovery that follows a stroke when
no other follows it; the game starts the next blow where the stroke ends.

## Motion capture: CMU

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
| `kick` | 135_04 (front kick) | 2.62 to 3.31 | straight ahead with the right leg, stepping in |
| `duck` | 13_17 (boxing) | 11.62 to 12.41 | down under a blow and back up |

These are put on the mannequin's skeleton by the tool, and the kick is
retimed: its wind-up and its recovery take 1.2 and 1.3 times as long as
performed, the last 0.12 s before it lands 0.65 of their time, and the
0.06 s after it 2.5 times theirs.

## Making it again

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/una-dinosauria/cmu-mocap /tmp/cmu
git -C /tmp/cmu sparse-checkout set --no-cone /data/013/13_17.bvh /data/135/135_04.bvh /data/137/137_41.bvh
# /tmp/ual2: UAL2_Standard.glb and UAL2_Standard_RM.glb, from the pack's "Unreal-Godot" folder
python3 tools/moves/build.py /tmp/cmu/data /tmp/ual2        # needs numpy
```

It prints, for each clip, when its fist or foot gets there, how far it
reaches and how far the body walks; the same numbers are stored in the
clip (`metadata/hit`, `next`, `reach`, `power`, `height`, `ducked`, and
`way_x`, `way_y`, `way_z`: which way the fist or foot is going when it
gets there) and read by `scripts/player/character.gd`.
