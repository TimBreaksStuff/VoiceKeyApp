#!/bin/zsh
# Runs the swift-testing suite with Command Line Tools only (no Xcode).
# CLT ships Testing.framework but SwiftPM doesn't add its search/plugin
# paths by itself — these flags do; without them: "no such module 'Testing'".
#
# It also declares a cross-import overlay — import Testing next to Foundation
# and the compiler reaches for _Testing_Foundation — while shipping that
# framework as a bare dylib with no Modules/ swiftinterface to import. Nothing
# on a machine without Xcode can satisfy it, so every test file that imports
# both fails with "no such module '_Testing_Foundation'". Declining the overlay
# costs only its Foundation conveniences (attaching a Data or URL to a test);
# the suite uses none of them. Drop the flag if it ever needs to.
set -euo pipefail
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
FRAMEWORKS="$CLT/Library/Developer/Frameworks"
PLUGINS="$CLT/usr/lib/swift/host/plugins/testing"

exec swift test \
  -Xswiftc -F"$FRAMEWORKS" \
  -Xswiftc -plugin-path -Xswiftc "$PLUGINS" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F"$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$@"
