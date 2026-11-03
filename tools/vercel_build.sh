#!/usr/bin/env bash
# Vercel build step: export the web build with the official Godot release.
# Runs on Vercel for every push, so each pull request gets a preview URL.
set -euo pipefail
cd "$(dirname "$0")/.."
godot="$(tools/install_godot.sh --templates-only=web | tail -n1)"
mkdir -p build/web && touch build/.gdignore
"$godot" --headless --path . --import >/dev/null 2>&1 || true
"$godot" --headless --path . --export-release "Web" build/web/index.html
ls -la build/web
