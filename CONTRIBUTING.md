# How a change goes in

1. **One change, one branch, one pull request** to `main`. If it builds on
   a pull request that is not merged yet, say so at the top and give the
   order to merge in.
2. **Check before pushing**, the same things CI will:

   ```sh
   pip install "gdtoolkit==4.5.0"
   gdlint scripts tests && gdformat --check scripts tests
   godot --headless --path . --import
   godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn
   ```

   A script with a warning that counts as an error (see `project.godot`)
   does not load: the tests fail.
3. **CI** (`.github/workflows/ci.yml`) runs lint, the tests, the physics
   perf gate, the web export and a probe that plays the export in headless
   Chromium. Vercel builds a preview of every push; the version at the top
   left of the game ends with the commit it was built from.
4. **Show it.** Anything you can see comes with a clip or a picture made
   by a scripted run, so it can be made again. Anything about speed or cost
   comes with numbers, and how they were measured
   (`docs/PERFORMANCE.md`).
5. **Say what is not there.** A pull request lists its limits.

## Code

- Typed GDScript; `gdformat` for the layout; constants, then variables,
  then functions.
- A tuning number is a constant with a comment: what it means, its unit.
- Tests are in `tests/test_*.gd`, methods `test_*`, and play the real
  scene. A new behaviour comes with one.
- Temporary instrumentation is marked `TMP` and never committed
  (`grep -rn "TMP\|tmp_" scripts tests shaders tools`).

## Assets

- Only what the game uses goes in the repository, with its licence in
  `CREDITS.md` and a `SOURCE.md` next to it.
- A new clip of the mannequin's library: add its name to `KEEP` in
  `tools/strip_clips.py` and run it on the original file.
- A new fighting move: add a line to `CLIPS` in `tools/mocap/build.py` and
  run it (`assets/fight/SOURCE.md`).
