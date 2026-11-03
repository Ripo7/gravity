#!/usr/bin/env bash
# Downloads the official Godot editor (and optionally export templates).
# Usage: tools/install_godot.sh [--templates] [--templates-only=web]
# Puts the binary at $GODOT_HOME/godot (default ~/.godot-ci) and prints its path.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$here/godot_version.env"
GODOT_HOME="${GODOT_HOME:-$HOME/.godot-ci}"
tag="${GODOT_VERSION}-${GODOT_STATUS}"
base="https://github.com/godotengine/godot/releases/download/${tag}"
mkdir -p "$GODOT_HOME"
cd "$GODOT_HOME"

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
extract() { # extract <zip> <dest> [members...]
  local zip="$1" dest="$2"; shift 2
  if command -v unzip >/dev/null; then unzip -q -o "$zip" "$@" -d "$dest"
  else python3 - "$zip" "$dest" "$@" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); members = sys.argv[3:] or None
z.extractall(sys.argv[2], members=members)
PY
  fi
}

if [ ! -x "$GODOT_HOME/godot" ]; then
  fetch "$base/Godot_v${tag}_linux.x86_64.zip" editor.zip
  extract editor.zip .
  mv "Godot_v${tag}_linux.x86_64" godot
  chmod +x godot
  rm editor.zip
fi

want_templates=""
only=""
for arg in "$@"; do
  case "$arg" in
    --templates) want_templates=1 ;;
    --templates-only=*) want_templates=1; only="${arg#*=}" ;;
  esac
done

if [ -n "$want_templates" ]; then
  tdir="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_STATUS}"
  if [ ! -f "$tdir/version.txt" ]; then
    mkdir -p "$tdir"
    fetch "$base/Godot_v${tag}_export_templates.tpz" templates.zip
    if [ "$only" = "web" ]; then
      extract templates.zip tmpl templates/version.txt templates/web_nothreads_release.zip templates/web_nothreads_debug.zip
    else
      extract templates.zip tmpl
    fi
    mv tmpl/templates/* "$tdir/"
    rm -rf tmpl templates.zip
  fi
fi
echo "$GODOT_HOME/godot"
