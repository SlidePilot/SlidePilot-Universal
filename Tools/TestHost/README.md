# SlidePilot Test Host

A small menu bar app that lets Claude test the Mac app without any permission for Claude itself (ADR 0018). It is the only process with Screen Recording and Accessibility, and it captures and controls only the SlidePilot **test build** (`<prefix>.SlidePilot.testhost`). Every rule is in `Sources/Policy.swift`.

## Set up (maintainer, once per host version)

Run this in your own terminal from an up-to-date `main` checkout:

```sh
Tools/TestHost/build.sh
```

1. Move `build/TestHost/SlidePilot Test Host.app` to `~/Applications` (replace the old one).
2. Open it. A camera icon appears in the menu bar, and macOS asks for **Screen Recording** and **Accessibility** (called **Device Control and Data Access** since macOS 27). Allow both in System Settings > Privacy & Security, only for "SlidePilot Test Host".
3. Quit and reopen the host once, so it picks up the grants. Its menu shows both as "allowed".

Optional: add it to System Settings > General > Login Items so it is always running.

The app is signed ad hoc, so macOS binds both grants to this exact binary. After any change to the host, the new build has no grants. System Settings still shows the old switches as on, but they belong to the old binary. So before you open a new build, quit the old one and reset both grants:

```sh
tccutil reset ScreenCapture local.slidepilot.testhost
tccutil reset Accessibility local.slidepilot.testhost
```

Then continue with step 2.

## What it does and does not do

- It acts only on a running app with the test build's bundle ID, a valid signature, the App Sandbox and no file access entitlements. Otherwise it refuses.
- Screenshots and recordings contain only the test build's windows (including its menus and sheets). Other apps, the desktop, notifications, the cursor and system panels are left out by macOS, even when they overlap.
- Input goes only to the test build. Clicks and drags briefly move the mouse pointer (it is put back afterwards) and happen only where a test build window is frontmost. Paste, AutoFill, Services, Open, Share, Print and Import are refused.
- It reads requests from and writes captures to `/private/tmp/claude/slidepilot-testhost`. It has no network access.
- Its menu shows the permissions, whether it is recording (red record icon) and the last action. Quit it whenever you don't want Claude to test the Mac app; Claude then falls back to app-rendered snapshots.

Claude's commands: `python3 -I scripts/mac-test-host.py --help`, see "Mac test host" in `CLAUDE.md`.
