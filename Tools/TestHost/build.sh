#!/bin/sh
# Builds "SlidePilot Test Host.app" into build/TestHost/ (ADR 0018).
# The app is signed ad hoc on purpose: macOS then binds the Screen Recording
# and Accessibility grants to this exact binary (its code hash). Any change to
# the sources produces a new binary without those grants.
#
# Usage: Tools/TestHost/build.sh
set -eu

cd "$(dirname "$0")/../.."

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

# The only app the host may capture or control: the test build's bundle ID.
prefix=""
for file in Config/Local.xcconfig Config/Shared.xcconfig; do
    if [ -z "$prefix" ] && [ -r "$file" ]; then
        prefix=$(sed -n 's/^[[:space:]]*BUNDLE_ID_PREFIX[[:space:]]*=[[:space:]]*\([A-Za-z0-9.-]*\).*/\1/p' "$file" | head -n 1)
    fi
done
if [ -z "$prefix" ]; then
    echo "BUNDLE_ID_PREFIX not found in Config/*.xcconfig" >&2
    exit 1
fi
target="$prefix.SlidePilot.testhost"

app="build/TestHost/SlidePilot Test Host.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
module_cache="${TMPDIR:-/tmp}/slidepilot-testhost-modules"

xcrun swiftc -swift-version 6 -O -warnings-as-errors \
    -target arm64-apple-macos26.0 \
    -module-cache-path "$module_cache" \
    -o "$app/Contents/MacOS/SlidePilotTestHost" \
    Tools/TestHost/Sources/*.swift

sed "s/__TARGET_BUNDLE_ID__/$target/" Tools/TestHost/Info.plist > "$app/Contents/Info.plist"
codesign --force --sign - --identifier local.slidepilot.testhost "$app"

echo "Built $app (captures and controls only $target)"
