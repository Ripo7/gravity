# Credits

The code is the project's own. What it uses:

| What | From | Terms |
| --- | --- | --- |
| The mannequin and 11 of its clips (`assets/mannequin/`) | [Quaternius, Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | CC0 |
| The fighting moves (`assets/fight/`) | [CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu/), BVH conversion by Bruce Hahne | free for research and commercial use |
| Two grid textures (`addons/kenney_prototype_textures/`) | [Kenney, Prototype Textures](https://kenney.nl/assets/prototype-textures), as packaged for Godot by [Calinou](https://github.com/Calinou/kenney-prototype-textures) | CC0 |
| The engine | [Godot](https://godotengine.org/) 4.7, with Jolt physics | MIT |

The data used in this project was obtained from mocap.cs.cmu.edu. The
database was created with funding from NSF EIA-0196217.

Where each file comes from, what was done to it and how to make it again:
`assets/mannequin/SOURCE.md`, `assets/fight/SOURCE.md`. Only what the
game uses is kept in the repository: the mannequin's file was cut down
from 46 clips to 11 (`tools/strip_clips.py`) and two textures out of 78
are left.

Before adding an asset: check its licence, add a line here, and a
`SOURCE.md` next to it.
