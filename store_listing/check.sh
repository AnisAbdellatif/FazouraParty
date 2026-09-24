#!/usr/bin/env bash
# Checks the store listing against the Play Console's limits: each text field
# in README.md, the feature graphic, and the phone screenshots.
# Play counts characters (code points), so this does too — not bytes.
set -euo pipefail
cd "$(dirname "$0")"

field() {
  sed -n "/<!-- listing:$1 -->/,/<!-- \/listing:$1 -->/p" README.md | sed '1d;$d'
}

status=0
for spec in name:30 short:80 full:4000; do
  key=${spec%%:*} limit=${spec##*:}
  count=$(field "$key" | python3 -c 'import sys; print(len(sys.stdin.read().rstrip("\n")))')
  if [ "$count" -eq 0 ]; then
    echo "$key: missing"; status=1
  elif [ "$count" -gt "$limit" ]; then
    echo "$key: $count / $limit — too long"; status=1
  else
    echo "$key: $count / $limit"
  fi
done

png_size() {
  python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(26); w,h=struct.unpack(">II",d[16:24]); print(w,h,d[25])' "$1"
}

# Play: "24-bit PNG (no alpha)" or JPEG. PNG colour type 2 is RGB.
read -r w h type <<<"$(png_size feature_graphic.png)"
if [ "$w" != 1024 ] || [ "$h" != 500 ] || [ "$type" != 2 ]; then
  echo "feature_graphic.png: ${w}x${h}, colour type $type — must be 1024x500 RGB"; status=1
else
  echo "feature_graphic.png: ${w}x${h}"
fi

# Phone screenshots: 4-8 of them, 16:9 or 9:16, each side 320-3840 px, <= 8 MB.
shots=(screenshots/[0-9]*.png)
if [ ! -e "${shots[0]}" ] || [ "${#shots[@]}" -lt 4 ] || [ "${#shots[@]}" -gt 8 ]; then
  echo "screenshots: ${#shots[@]}, Play takes 4 to 8"; status=1
fi
for shot in "${shots[@]}"; do
  [ -e "$shot" ] || continue
  read -r w h type <<<"$(png_size "$shot")"
  bytes=$(wc -c <"$shot")
  if [ $((w * 16)) -ne $((h * 9)) ] && [ $((w * 9)) -ne $((h * 16)) ]; then
    echo "$shot: ${w}x${h} is not 16:9 or 9:16"; status=1
  elif [ "$w" -lt 320 ] || [ "$h" -lt 320 ] || [ "$w" -gt 3840 ] || [ "$h" -gt 3840 ]; then
    echo "$shot: ${w}x${h}, each side must be 320-3840 px"; status=1
  elif [ "$bytes" -gt 8388608 ]; then
    echo "$shot: $bytes bytes, over 8 MB"; status=1
  elif [ "$type" != 2 ]; then
    echo "$shot: colour type $type, must be RGB without alpha"; status=1
  else
    echo "$shot: ${w}x${h}, $((bytes / 1024)) KB"
  fi
done
exit $status
