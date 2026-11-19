# Credits

The code is the project's own. What it uses:

| What | From | Terms |
| --- | --- | --- |
| The mannequin and 8 of its clips (`assets/mannequin/`) | [Quaternius, Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | CC0 |
| The blows (`assets/fight/`) | [Quaternius, Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html), free "Standard" version | CC0 |
| The engine | [Godot](https://godotengine.org/) 4.7, with Jolt physics | MIT |

Nothing of the CMU Graphics Lab Motion Capture Database is in the game
at present (the kick, which came from it, is out); the tool that reads
it is kept, see `assets/fight/SOURCE.md`.

Where each file comes from, what was done to it and how to make it again:
`assets/mannequin/SOURCE.md`, `assets/fight/SOURCE.md`. Only what the
game uses is kept in the repository: the mannequin's file was cut down
from 46 clips to 8 (`tools/strip_clips.py`).

Before adding an asset: check its licence, add a line here, and a
`SOURCE.md` next to it.
