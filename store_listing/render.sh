#!/usr/bin/env bash
# Renders the Play listing's images from their sources:
#   feature_graphic.svg                    -> feature_graphic.png (1024x500)
#   screenshots/raw/*.png + captions.txt   -> screenshots/*.png   (1080x1920)
#
# The raw screenshots come from the app's own screens:
#   cd app && flutter test tool/store_screenshots/screenshots_test.dart
#
# Uses the fonts bundled with the app, so the result doesn't depend on what is
# installed, and writes 24-bit PNGs without alpha, which is what Play asks for.
set -euo pipefail
cd "$(dirname "$0")"
here="$(pwd)"
fonts="$(cd ../app/assets/fonts && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/fonts.conf" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <dir>$fonts</dir>
</fontconfig>
XML

render() { # <svg> <png> <width> <height>
  FONTCONFIG_FILE="$work/fonts.conf" "${INKSCAPE:-inkscape}" "$1" \
    --export-type=png --export-filename="$2" \
    --export-width="$3" --export-height="$4" \
    --export-background-opacity=1 --export-png-color-mode=RGB_8 2>/dev/null
  echo "wrote store_listing/${2#"$here"/}"
}

render feature_graphic.svg "$here/feature_graphic.png" 1024 500

escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

while IFS='|' read -r name line1 line2; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  raw="$here/screenshots/raw/$name.png"
  if [[ ! -f "$raw" ]]; then
    echo "missing $raw — run the screenshot test in app/ first" >&2
    exit 1
  fi
  svg="$work/$name.svg"
  l1="$(escape "$line1")" l2="$(escape "$line2")"
  sed -e "s|{{IMAGE}}|$raw|" -e "s|{{LINE1}}|$l1|" -e "s|{{LINE2}}|$l2|" \
    screenshots/frame.svg > "$svg"
  render "$svg" "$here/screenshots/$name.png" 1080 1920
done < screenshots/captions.txt
