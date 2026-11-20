#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
  Sources/WindowTracking.swift Tests/main.swift -framework AppKit -o build/tracking-tests
build/tracking-tests
if [[ "${1:-}" == "--fixture" ]]; then
  APP="$PWD/build/FollowFixture.app"
  mkdir -p "$APP/Contents/MacOS"
  xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path "$PWD/build/module-cache" \
    Tests/Fixture.swift -framework AppKit -o "$APP/Contents/MacOS/FollowFixture"
  cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexboot.fixture</string>
<key>CFBundleName</key><string>FollowFixture</string>
<key>CFBundleExecutable</key><string>FollowFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
  codesign --force --sign - "$APP"
  if [[ -d build/CodexBootAnimation.app ]]; then
    ditto build/CodexBootAnimation.app build/FollowOverlay.app
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.codexboot.demo' build/FollowOverlay.app/Contents/Info.plist
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName FollowOverlay' build/FollowOverlay.app/Contents/Info.plist
    codesign --force --sign - build/FollowOverlay.app
  fi
fi
