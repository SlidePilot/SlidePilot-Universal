# 0018 – Mac test host: capture and drive only the SlidePilot test build

- Status: Accepted
- Date: 2026-11-18

## Context
Claude could test the iPad app in the simulator (screenshots, taps, keys), but on the Mac it only had snapshots that the app renders from its own views (`SlidePilotMacSnapshots`). Those miss menus, popovers, real Liquid Glass and window behavior, and Claude could not click through the app at all. So every Mac behavior ended up as a manual step in "How to verify".

Granting Screen Recording or Accessibility to Claude, Terminal or Xcode is not acceptable: every process Claude starts would inherit it and could see or control the whole Mac. XCUITest is no better: its screenshots are screen crops that show overlapping windows of other apps, and a UI test can read any app's accessibility tree.

## Decision
A small, separate helper app, **SlidePilot Test Host** (`Tools/TestHost/`), is the only process with Screen Recording and Accessibility. Claude talks to it through files and never gets either permission itself.

- **Only the test build.** The host captures and controls exactly one bundle ID, `<prefix>.SlidePilot.testhost`, sealed into its own Info.plist. It refuses every command unless exactly one such app is running with a valid code signature, in the App Sandbox, with no entitlements beyond sandbox, debugging and network (no file access, no temporary exceptions, no contacts or devices).
- **The OS enforces the crop.** Screenshots and recordings use ScreenCaptureKit filters that include only the test build's process (or one of its windows). Other apps, the desktop, notifications and out-of-process panels (open/save panel, AutoFill) are left out even when they overlap. The cursor is never captured.
- **Input only to the test build.** Accessibility calls start at the test build's process; keyboard and mouse events are posted to its process ID. Points must lie inside one of its windows.
- **No outside data.** The test build is the Debug app with suffix `.testhost` (own container: no recents, no restored windows), no user-selected file access, launched in English. Documents can only come from the host's inbox, which Claude fills from `Fixtures/` (symbolic and hard links are refused). Paste, AutoFill, Services, Open, Share, Print and Import are refused as menu items and as shortcuts (⌘V, ⌘O); while a menu is open only Escape is accepted, so Return cannot choose a blocked item.
- **Grant bound to the reviewed binary.** The host is signed ad hoc, so its designated requirement is its code hash. macOS binds the grants to that exact binary: any change to the host (by anyone, including Claude) produces a binary without them, and macOS asks the maintainer again. The maintainer builds it from `main`, installs it in `~/Applications` and grants the permissions once per version.
- **Exchange through files.** Requests, responses, the inbox and captures live in `/private/tmp/claude/slidepilot-testhost` (writable from Claude's sandbox). The host checks that these are real folders owned by the user. It has no network listener.
- **Everything else stays banned.** `scripts/check-no-screen-capture.sh` still fails on screen capture APIs anywhere except `Tools/TestHost/`. `screencapture`, `open` and `osascript` stay denied for Claude.
- App-rendered snapshots (`SlidePilotMacSnapshots`) stay as the fallback when the host is not running and in CI.
- PR "How to verify" lists only what Claude could not check itself with the simulator or the test host.

## Consequences
- Claude can launch the test build with fixtures, click, type, use menus, draw, take screenshots (also of menus and real Liquid Glass) and record short videos, in light and dark mode.
- The protection relies on the host's code (`Tools/TestHost/Sources/Policy.swift` holds all rules) and on the code hash binding. Every change to the host needs a careful review and a new grant.
- The test build has no user-selected file access, so the open panel and import cannot be tested this way; they stay in "How to verify".
- Residual risks: the test build itself can show what a sandboxed app sees (its own container, network content the app loads); typing text into the test build is allowed. Contact AutoFill suggestions that a text field may show come from another process and are not captured; choosing one by keyboard is not blocked.
- The test build uses the bundle ID `<prefix>.SlidePilot.testhost`, signed ad hoc and never registered as an App ID (ADR 0014 still applies to real App IDs).
