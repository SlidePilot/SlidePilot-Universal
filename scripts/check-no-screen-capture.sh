#!/bin/sh
# Fails if code in this repository uses an API that can capture the screen or
# other apps' windows. SlidePilot never needs one: Mac snapshots are rendered
# by the app from its own views (SlidePilotMacSnapshots/WindowSnapshot.swift).
# Runs in CI; add new folders with code to SOURCES.
set -eu

cd "$(dirname "$0")/.."

SOURCES="SlidePilot SlidePilotMacSnapshots Packages scripts .github .claude"
PATTERN='import[[:space:]]+ScreenCaptureKit|SCShareableContent|SCScreenshotManager|SCContentFilter|SCStream[^a-z]|CGWindowListCreateImage|CGWindowListCopyWindowInfo|CGDisplayCreateImage|CGDisplayStream|CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|AVCaptureScreenInput|com\.apple\.security\.screen-capture|usr/sbin/screencapture|"screencapture"|'"'"'screencapture'"'"'|^[[:space:]]*screencapture[[:space:]]'

# Lines in this script and the deny rules in .claude/settings.json name the
# APIs on purpose, so they are excluded.
matches=$(grep -rInE "$PATTERN" $SOURCES \
    --exclude=check-no-screen-capture.sh \
    --exclude=settings.json \
    --exclude-dir=.build || true)

if [ -n "$matches" ]; then
    echo "Screen capture APIs are not allowed in SlidePilot:"
    echo "$matches"
    exit 1
fi
echo "No screen capture APIs found."
