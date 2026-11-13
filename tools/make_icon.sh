#!/bin/zsh
# Builds Resources/AppIcon.icns from Icon/AppIcon.icon/Assets/mark.png.
# The picture is copied through. Nothing is redrawn.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
src="$repo/Icon/AppIcon.icon/Assets/mark.png"
[[ -f "$src" ]] || { echo "missing $src"; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
set="$work/AppIcon.iconset"
mkdir -p "$set" "$repo/Resources"

pair() { # pixel size, filename
  if [[ "$1" == "1024" ]]; then
    cp "$src" "$set/$2"
  else
    sips -z "$1" "$1" "$src" --out "$set/$2" >/dev/null
  fi
}
pair 16 icon_16x16.png
pair 32 icon_16x16@2x.png
pair 32 icon_32x32.png
pair 64 icon_32x32@2x.png
pair 128 icon_128x128.png
pair 256 icon_128x128@2x.png
pair 256 icon_256x256.png
pair 512 icon_256x256@2x.png
pair 512 icon_512x512.png
pair 1024 icon_512x512@2x.png

iconutil -c icns "$set" -o "$repo/Resources/AppIcon.icns"
rm -f "$repo/Resources/Assets.car"
echo "wrote Resources/AppIcon.icns"
