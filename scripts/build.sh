#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/CodexBootAnimation.app"
ARCH="${ARCH:-$(uname -m)}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" \
  -module-cache-path "$PWD/build/module-cache" Sources/*.swift \
  -framework AppKit -framework QuartzCore -framework AVFoundation -o "$APP/Contents/MacOS/CodexBootAnimation"
for skin in DragonCodex EmeraldAwakening; do
  mkdir -p "$APP/Contents/Resources/$skin"
  cp "Assets/$skin/"{intro.mp4,loop.mp4,full_preview.mp4,poster.jpg} "$APP/Contents/Resources/$skin/"
done
# The old film remains in Assets. Remove its generated bundle copies on upgrade.
rm -f "$APP/Contents/Resources/"Paper-Swallow{.mp4,-loop.mp4,-poster.png} "$APP/Contents/Resources/background.png" "$APP/Contents/Resources/Emerald-Orbit.mp4" "$APP/Contents/Resources/Emerald-Orbit-loop.mp4"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.codexboot.animation</string>
  <key>CFBundleName</key><string>CodexBootAnimation</string>
  <key>CFBundleDisplayName</key><string>Codex OpenSkin</string>
  <key>CFBundleExecutable</key><string>CodexBootAnimation</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.6.0</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
