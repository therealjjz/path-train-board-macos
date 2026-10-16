#!/bin/zsh
# Regenerates the README screenshots (docs/) and the app icon (assets/AppIcon.icns)
# from live PATH data. Run after ./build.sh.
set -e
cd "$(dirname "$0")/.."
mkdir -p docs assets
build/Tubes.app/Contents/MacOS/Tubes --render-assets docs

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s docs/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) docs/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
echo "Wrote docs/*.png and assets/AppIcon.icns"
