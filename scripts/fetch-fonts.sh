#!/usr/bin/env bash
# Downloads the open-source (SIL OFL) Arabic fonts bundled with the app.
set -euo pipefail

DEST="App/Resources/Fonts"
BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"
mkdir -p "$DEST"

fetch() {
  local path="$1" file
  file="$(basename "$path")"
  echo "Downloading $file"
  curl -fsSL --retry 3 -o "$DEST/$file" "$BASE/$path"
}

fetch amiri/Amiri-Regular.ttf
fetch amiri/Amiri-Bold.ttf
fetch tajawal/Tajawal-Regular.ttf
fetch tajawal/Tajawal-Bold.ttf
fetch scheherazadenew/ScheherazadeNew-Regular.ttf
fetch scheherazadenew/ScheherazadeNew-Bold.ttf

ls -l "$DEST"
