#!/bin/zsh
# Runs the swift-testing suite with Command Line Tools only (no Xcode).
# CLT ships Testing.framework but SwiftPM doesn't add its search/plugin
# paths by itself — these flags do; without them: "no such module 'Testing'".
set -euo pipefail
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
FRAMEWORKS="$CLT/Library/Developer/Frameworks"
PLUGINS="$CLT/usr/lib/swift/host/plugins/testing"

exec swift test \
  -Xswiftc -F"$FRAMEWORKS" \
  -Xswiftc -plugin-path -Xswiftc "$PLUGINS" \
  -Xlinker -F"$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$@"
