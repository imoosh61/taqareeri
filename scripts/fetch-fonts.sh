#!/usr/bin/env bash
# Downloads open-source (SIL OFL) Arabic fonts from github.com/google/fonts at build time.
# Each family is tried as static Regular/Bold files first, then as a variable font.
# Missing families are skipped with a warning; the app discovers whatever was bundled.
set -uo pipefail

DEST="App/Resources/Fonts"
LICENSES="App/Resources/Licenses"
BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"
mkdir -p "$DEST" "$LICENSES"

license() { # family dir → bundled OFL text (required by the SIL Open Font License)
  get "$BASE/$2/OFL.txt" "$LICENSES/$1-OFL.txt" || rm -f "$LICENSES/$1-OFL.txt"
}

get() { # url → file ; returns curl status
  curl -fsSL --retry 2 -o "$2" "$1" 2>/dev/null
}

FAMILIES=(
  Amiri ScheherazadeNew Tajawal Almarai Cairo NotoNaskhArabic NotoKufiArabic NotoSansArabic
  IBMPlexSansArabic Lateef Harmattan ArefRuqaa Mirza MarkaziText ReemKufi ElMessiri Changa
  ReadexPro Vazirmatn Kufam Lalezar Rakkas Katibeh Qahiri Alkalami Marhey Lemonada BalooBhaijaan2
)
VARIABLE_AXES=("wght" "slnt,wght" "HEXP,wght" "wdth,wght")

ok=0
for family in "${FAMILIES[@]}"; do
  dir="$(echo "$family" | tr '[:upper:]' '[:lower:]')"
  if get "$BASE/$dir/$family-Regular.ttf" "$DEST/$family-Regular.ttf"; then
    get "$BASE/$dir/$family-Bold.ttf" "$DEST/$family-Bold.ttf" || true
    license "$family" "$dir"
    echo "✓ $family (static)"; ok=$((ok + 1)); continue
  fi
  rm -f "$DEST/$family-Regular.ttf"
  found=0
  for axes in "${VARIABLE_AXES[@]}"; do
    if get "$BASE/$dir/$family%5B$axes%5D.ttf" "$DEST/$family-VF.ttf"; then
      license "$family" "$dir"
      echo "✓ $family (variable: $axes)"; ok=$((ok + 1)); found=1; break
    fi
  done
  if [ $found -eq 0 ]; then
    rm -f "$DEST/$family-VF.ttf"
    echo "::warning::Font family $family not found, skipped"
  fi
done

echo "Downloaded $ok font families"
ls -l "$DEST"
[ $ok -gt 0 ] || { echo "::error::No fonts downloaded"; exit 1; }
