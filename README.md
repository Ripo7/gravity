# Concept

A clean starting point for the next game concept: Godot 4.7, GDScript,
Jolt physics, Compatibility renderer (WebGL2), so every idea can be played
in Safari on an iPhone from its pull request.

The previous project, Gravity (first-person destruction sandbox), is kept
as it was on the branch [`archive/gravity`](../../tree/archive/gravity).

## What is here

- `scenes/main.tscn` + `scripts/main.gd`: a floor, a camera, crates that
  fall where you tap or click. Replace it with the concept.
- `tests/`: a small headless test runner; files `tests/test_*.gd`,
  methods `test_*` (they may `await`).
- `.github/workflows/ci.yml`: lint, tests and a web export on every pull
  request.
- `vercel.json` + `tools/vercel_build.sh`: Vercel builds the web export
  for every push, so each pull request gets a preview URL.
- `tools/godot_version.env`: the engine version used everywhere.

## Run

```sh
godot --path .                                                # play
godot --headless --path . res://tests/test_runner.tscn        # tests
godot --headless --path . res://tests/test_runner.tscn -- --only=main
pip install "gdtoolkit==4.*" && gdlint scripts tests && gdformat --check scripts tests
```

`tools/install_godot.sh` downloads the right Godot (and `--templates` the
export templates) into `~/.godot-ci`.
