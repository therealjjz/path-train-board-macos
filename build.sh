#!/bin/zsh
# Builds Tubes.app (universal: Apple silicon + Intel) into ./build
#   ./build.sh            build the app
#   ./build.sh --zip      also make build/Tubes.zip for a GitHub release
set -e
cd "$(dirname "$0")"

VERSION=1.0.0
APP=build/Tubes.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for ARCH in arm64 x86_64; do
  swiftc -O -parse-as-library -target $ARCH-apple-macos15 \
    Sources/*.swift -o build/obj/Tubes-$ARCH
done
lipo -create build/obj/Tubes-arm64 build/obj/Tubes-x86_64 -output "$APP/Contents/MacOS/Tubes"

[[ -f assets/AppIcon.icns ]] && cp assets/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Tubes</string>
  <key>CFBundleDisplayName</key><string>Tubes</string>
  <key>CFBundleIdentifier</key><string>io.github.therealjjz.Tubes</string>
  <key>CFBundleExecutable</key><string>Tubes</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.travel</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "$1" == "--zip" ]]; then
  rm -f build/Tubes.zip
  ditto -c -k --keepParent "$APP" build/Tubes.zip
  echo "Packed build/Tubes.zip"
fi
