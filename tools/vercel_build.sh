#!/usr/bin/env bash
# Vercel build step: export the web build with the official Godot release.
# Runs on Vercel for every push, so each pull request gets a preview URL.
set -euo pipefail
cd "$(dirname "$0")/.."
godot="$(tools/install_godot.sh --templates-only=web | tail -n1)"
mkdir -p build/web && touch build/.gdignore
# The build says which commit it is (shown at the top left of the game), so
# a preview tested on a phone can be told from the next one.
commit="${VERCEL_GIT_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo dev)}"
sed -i -E "s|^config/version=\"([^\"+]*)[^\"]*\"|config/version=\"\1+${commit:0:7}\"|" project.godot
grep "^config/version" project.godot
# The first import can exit non-zero on a fresh checkout; keep going, but
# keep its errors in the build log so a broken resource is visible.
"$godot" --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT ERROR|Failed" || true
"$godot" --headless --path . --export-release "Web" build/web/index.html
ls -la build/web
