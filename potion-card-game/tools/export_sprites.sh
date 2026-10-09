#!/usr/bin/env bash
# Exports the greyscale .aseprite sources to PNGs used by the game.
set -euo pipefail
SRC="${1:-$HOME/Desktop/Sprites/Potion Card Game}"
ASEPRITE="${ASEPRITE:-$HOME/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/sprites"
mkdir -p "$OUT"
for f in "$SRC"/*.aseprite; do
	name="$(basename "$f" .aseprite)"
	"$ASEPRITE" -b "$f" --save-as "$OUT/$name.png"
	echo "exported $name.png"
done
