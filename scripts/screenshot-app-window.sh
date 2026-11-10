#!/bin/sh
# Captures exactly one window of the locally built SlidePilot app (never the
# whole screen, never another app). Usage: scripts/screenshot-app-window.sh <output.png>
# This is the only allowed way for Claude Code to take Mac screenshots
# (see "Privacy" in CLAUDE.md); direct `screencapture` calls are denied.
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <output.png>" >&2
    exit 2
fi
case "$1" in
    *.png) ;;
    *) echo "output must be a .png file" >&2; exit 2 ;;
esac

script_dir=$(cd "$(dirname "$0")" && pwd)
if ! window_id=$(swift "$script_dir/find-app-window.swift"); then
    echo "No window of a locally built SlidePilot app is on screen. Start the app from Xcode/xcodebuild first." >&2
    exit 1
fi

# -l: only this window, -o: no shadow, -x: no sound.
/usr/sbin/screencapture -o -x -l"$window_id" "$1"
echo "Saved window $window_id to $1"
