#!/bin/sh
# Copies the fixture PDFs into "On My iPad/SlidePilot Fixtures" of an iOS simulator,
# so they can be opened from SlidePilot's document browser.
#
# Usage (from the repository root): scripts/sim-copy-fixtures.sh <simulator UDID>
# Find the UDID with: xcrun simctl list devices available
#
# Writes only into the simulator's local Files storage, which the Claude Code sandbox
# allows (.claude/settings.json, sandbox.filesystem.allowWrite).
set -eu

udid="${1:-}"
if ! printf '%s' "$udid" | grep -Eq '^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$'; then
    echo "usage: $0 <simulator UDID>" >&2
    exit 64
fi
if [ ! -d Fixtures ]; then
    echo "Run this from the repository root." >&2
    exit 66
fi

groups="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Containers/Shared/AppGroup"
storage=""
for group in "$groups"/*; do
    metadata="$group/.com.apple.mobile_container_manager.metadata.plist"
    [ -f "$metadata" ] || continue
    identifier=$(/usr/libexec/PlistBuddy -c 'Print MCMMetadataIdentifier' "$metadata" 2>/dev/null || true)
    if [ "$identifier" = "group.com.apple.FileProvider.LocalStorage" ]; then
        storage="$group/File Provider Storage"
    fi
done
if [ -z "$storage" ] || [ ! -d "$storage" ]; then
    echo "No \"On My iPad\" storage found. Boot the simulator once and open the Files app, then try again." >&2
    exit 69
fi

destination="$storage/SlidePilot Fixtures"
mkdir -p "$destination/media"
cp Fixtures/*.pdf Fixtures/*.rtf "$destination/"
# media.pdf links to media/ relative to itself.
cp Fixtures/media/* "$destination/media/"
echo "Copied fixtures to On My iPad/SlidePilot Fixtures on $udid."
