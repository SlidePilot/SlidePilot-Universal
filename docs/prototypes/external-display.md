# Prototype: presentation on a second screen (Mac) and external display (iPad)

Issue #7 · Parity DOC-04, DOC-05, DOC-06 · Phase 1 – Risk Prototypes

## Question

The old app opens the presentation window on `NSScreen.screens[1]` and always enters full screen, even on a single screen (DOC-05). The new app is SwiftUI on macOS 26 and iPadOS 26. This prototype checks whether SwiftUI can place a window on a specific screen and enter full screen, how the app reacts when screens are added or removed while presenting, how an iPad drives an external display without mirroring, and how AirPlay behaves on both platforms.

## What was tried

Prototype code on the branch `proto/external-display` (draft PR #49, closed, not merged). One shared observable session drives a presenter window and a presentation surface that renders the slide at the pixel size of its display. A diagnostics inspector shows screens or scenes and keeps an event log that can be copied, so hardware tests could be reported without screenshots.

| Platform | Variant | How |
|---|---|---|
| macOS | Placement A | `Window` scene for the presentation, then AppKit `setFrame` to `NSScreen.screens[1]` (like the old app) |
| macOS | Placement B | SwiftUI `defaultWindowPlacement`; the target frame still comes from `NSScreen`, because `WindowPlacementContext` only exposes the default display |
| macOS | Full screen | `NSWindow.toggleFullScreen` after placement (SwiftUI has no API for it), then the presenter is made key again |
| macOS | Screen changes | `didChangeScreenParametersNotification`; optional auto-move to the new screen (exit full screen, `setFrame`, enter full screen) |
| iPadOS | External display | App delegate adaptor hands the `windowExternalDisplayNonInteractive` role to a UIKit scene delegate that hosts the SwiftUI presentation view |
| iPadOS | Extended display | The presentation opened as a normal window (Stage Manager) |

**Environment:** Apple-silicon MacBook (built-in screen 1512×982 pt @2x), external 5K display over cable (2560×1440 pt @2x), Apple TV over AirPlay. A real iPad with an external display over cable and the same Apple TV. Debug builds from Xcode.

## Results

### Mac

| Test | Setup | Result |
|---|---|---|
| M1 | Built-in screen only | OK. Presentation in full screen in its own Space; the presenter keeps the keyboard focus |
| M2 | Second screen connected before opening | OK with A and B. Full screen on screen #1, presenter key. Slide rendered at full resolution (3840×2880 px in 5–8 ms) |
| M3 | Screen plugged in while presenting full screen on the built-in screen | **Fails.** Nothing happens on its own (expected without auto-move). The move to the new screen, by button or by auto-move, leaves the window on screen #0 |
| M4 | Apple TV, "Use as Separate Display" | OK, same as M2. AirPlay appears as a normal second `NSScreen` |
| M5 | Apple TV, mirroring | The TV mirrors the built-in screen. The app sees one screen, so the audience sees the presenter Space |

**Placement A vs. B.** Both end on the right screen. A creates the window on screen #0 and moves it about 150 ms later. B creates it directly on screen #1 (log: window created with frame on screen #1), so nothing appears on the presenter screen first.

**Why M3 fails.** The move first calls `toggleFullScreen` to leave full screen, waits for `didExitFullScreen`, then sets the frame and enters full screen again. The exit notification never arrives: the log shows no "exited full screen" and the move gives up after its 3 s timeout ("moved presentation to screen #1 → #0"). The presentation sits in its own full-screen Space while the user looks at the presenter Space; macOS ignores `toggleFullScreen` for that window. `setFrame` on a full-screen window has no effect.

**Not tested:** unplugging a screen while the presentation is on it (the move never got there).

### iPad

| Test | Setup | Result |
|---|---|---|
| I1 | Display over cable, Stage Manager off | OK. The display shows only the slide on black, the iPad keeps the presenter. Disconnect and reconnect work |
| I2 | Cable, Stage Manager on, presentation opened as a window | OK. The window opens directly on the external display |
| I3 | Apple TV, Screen Mirroring from Control Center | OK while the app is in the foreground: the external-display scene replaces the mirror and shows only the slide. In the background the system mirrors the iPad again |
| I4 | Display connected before launching the app | OK. The scene connects at launch and shows the presentation |

Cable and AirPlay use the same external-display scene path; no AirPlay-specific code is needed. There is no API to start AirPlay screen mirroring from the app; the user starts it from Control Center.

## Limits

- **SwiftUI cannot choose a screen.** `WindowPlacementContext` only exposes the default display; the target frame needs `NSScreen`.
- **SwiftUI cannot enter full screen.** It needs `NSWindow.toggleFullScreen`.
- **A full-screen window in a hidden Space cannot be moved.** `toggleFullScreen` is ignored, so exit-move-enter does not work while presenting.
- **Mac AirPlay mirroring** shows the presenter Space; only "Use as Separate Display" gives a presentation screen.
- **iPad:** SwiftUI has no scene type for the external-display role; it needs an app delegate adaptor and a UIKit scene delegate. The scene only replaces the mirror while the app is in the foreground.

## Product decisions

Approved by the product owner after the tests. They change DOC-05 (see `docs/feature-parity.md`).

**Mac**
1. **Opening a document:** with a second screen, the presentation starts automatically on it in full screen. With only the built-in screen, only the presenter window opens.
2. **Start Presentation:** a toolbar button in the presenter window (not only in a menu) with a keyboard shortcut, also in the menu for discoverability. It starts the presentation and reopens a closed presentation window. There is no stop button; closing the window ends the presentation.
3. **Single screen:** a started presentation runs in full screen in its own Space.
4. **Screen added, no presentation running:** nothing opens. Connecting a display must not open windows as a side effect.
5. **Screen added while presenting:** the presentation moves to the new screen automatically, in full screen. The presenter keeps the focus.
6. **Screen removed while presenting:** the presentation keeps running on the remaining screen (to be verified in #13; it was not reached in M3).

**iPad**
7. **External display (cable or AirPlay) connected:** the app takes over the display at once. With a document open it shows the presentation; without one it shows a ready screen with the app logo and a short text (for example "Ready to present"). This differs from the Mac on purpose: the system hands the app a display, no window opens.
8. **No external display:** the iPad shows only the presenter.

**AirPlay (both platforms):** supported and tested in 1.0, with no AirPlay UI in the app. Mac: "Use as Separate Display" behaves like a cable display. iPad: AirPlay mirroring is handled by the external-display scene.

## Recommendation

1. **Mac placement:** SwiftUI `Window` scene for the presentation with `defaultWindowPlacement` (variant B), target frame from `NSScreen`. Wrap all AppKit glue (screen list, full screen, key window, screen notifications) in one macOS-only type.
2. **Mac full screen:** `toggleFullScreen` once the window is placed; make the presenter key afterwards.
3. **Mac move while presenting:** do not exit and re-enter full screen. **Close the presentation window and open it again;** placement B then creates it on the new screen and it enters full screen there. Same for a removed screen if macOS does not handle it well. Verify on hardware in #13 (M3 again, including unplugging).
4. **Screen observation:** one observer of screen changes owned by the macOS glue, as an `AsyncStream`, cancelled with its owner. React only while a presentation is running.
5. **iPad:** app delegate adaptor plus UIKit scene delegate for `windowExternalDisplayNonInteractive`, hosting the SwiftUI presentation view or the ready screen. The scene finds the active document's session through an app-level registry of presenting sessions, not a global singleton.
6. **Documentation for users:** on the Mac, choose "Use as Separate Display" for AirPlay; on the iPad, keep SlidePilot in the foreground while presenting over AirPlay.

## Follow-ups

- #13 (presenter and presentation windows): implement the decisions and recommendations above; repeat M3 (screen added while presenting, then unplugged) on hardware.

## Re-running

Check out `proto/external-display` and run the scheme `SlidePilot` on a Mac or a real iPad (the simulator has no AirPlay). Click Open Sample, open the Diagnostics inspector and use Copy Log after each step. The Mac inspector has the placement picker, the full-screen and auto-move toggles and manual move buttons.
