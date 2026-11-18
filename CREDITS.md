# Credits

The code is the project's own. What it uses:

| What | From | Terms |
| --- | --- | --- |
| The mannequin and 8 of its clips (`assets/mannequin/`) | [Quaternius, Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | CC0 |
| The blows (`assets/fight/`) | [Quaternius, Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html), free "Standard" version | CC0 |
| The kick (`assets/fight/`) | [CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu/), BVH conversion by Bruce Hahne | free for research and commercial use |
| The engine | [Godot](https://godotengine.org/) 4.7, with Jolt physics | MIT |

The data used in this project was obtained from mocap.cs.cmu.edu. The
database was created with funding from NSF EIA-0196217.

Where each file comes from, what was done to it and how to make it again:
`assets/mannequin/SOURCE.md`, `assets/fight/SOURCE.md`. Only what the
game uses is kept in the repository: the mannequin's file was cut down
from 46 clips to 8 (`tools/strip_clips.py`).

Before adding an asset: check its licence, add a line here, and a
`SOURCE.md` next to it.
