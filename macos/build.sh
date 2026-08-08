#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/VoiceKey.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/VoiceKey "$APP/Contents/MacOS/"
# SPM dependency resource bundles (WhisperKit/swift-transformers emit these)
cp -R .build/release/*.bundle "$APP/Contents/Resources/" 2>/dev/null || true
# app icon — iconutil requires the .iconset suffix; CFBundleIconFile points at it
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# "VoiceKey Dev" is a self-signed code-signing cert in the login keychain —
# stable identity, so TCC grants (Accessibility/Microphone) survive rebuilds.
# Falls back to ad-hoc if the cert is missing.
if security find-identity -v -p codesigning | grep -q "VoiceKey Dev"; then
  codesign --force --sign "VoiceKey Dev" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "built $APP"
[ "${1:-}" = "--run" ] && open "$APP" || true
