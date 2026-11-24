# Older macOS versions: analysis

Analysis for issue #84. ADR 0001 sets the deployment target to macOS 26 and iPadOS 26. This document shows what it would take to support older macOS versions, so users there are not limited to SlidePilot 1.8. iPadOS is out of scope.

## Decision
The product owner decided to **keep macOS 26 and iOS/iPadOS 26** as the minimum (ADR 0001 unchanged). Reasons: a moderate, shrinking gain (users below macOS 26 keep SlidePilot 1.8, and remote would be missing on macOS 15 anyway) against lasting costs (availability checks in new code, an extra CI job, a manual check in a macOS 15 VM per release) and unknown runtime behavior shortly before the release. iPad and iPhone never had an older SlidePilot, so no users are left behind there. The analysis below stays as the reference if the question comes up again.

## Method
The Mac app and all three packages were built locally with `MACOSX_DEPLOYMENT_TARGET=15.0` and `14.0` (Xcode 27.2, macOS 27.2 SDK, `-continue-building-after-errors`). Each availability error was temporarily patched or marked `@available` until the build had no new errors; the patches were not committed. The build covers the macOS code paths only; nothing was run on an older system.

## What needs macOS 26
Found by the macOS 15 build. Everything else in the packages and the app compiles for macOS 15.

| API | Where | Feature |
|---|---|---|
| Swift Network API: `NetworkListener`, `NetworkBrowser`, `NetworkConnection<TCP>`, `Bonjour.Endpoint`, `TCP` | `SlidePilot/Remote/RemoteNetwork.swift:13-79`, `SlidePilot/Remote/RemoteService.swift:226` | Remote (host and controller), ADR 0015/0017 |
| `Observations` (Observation) | `Packages/SlidePilotCore/Sources/SlidePilotCore/DisplayAwakeKeeper.swift:26`, `SlidePilot/Remote/RemoteService.swift:115` | Keep display awake (SET-04), remote host state |
| `.glassEffect(_:in:)` | `SlidePilot/Presenter/SlideNavigator.swift:228` | Page number field above the navigator |
| `ToolbarItem.sharedBackgroundVisibility(_:)` | `SlidePilot/Presenter/PresenterCurtain.swift:38` | Hidden-screen warning in the toolbar |
| `ToolbarSpacer` | `SlidePilot/Remote/RemoteSlidesView.swift:60` | Remote mode toolbar |
| `Button(role: .close)` | `SlidePilot/Remote/RemoteControlView.swift:85` | Remote device list sheet |

The remote types (`RemoteService`, `RemoteControl`) are used by `SlidePilotApp`, `RemoteEnvironment`, `RemoteControlView`, `RemoteSlidesView` and `RemoteSettingsView`; gating the remote gates these too. Liquid Glass of standard components (toolbars, sidebars, sheets) needs no change: on older systems they draw in that system's style.

## What needs macOS 15
Found by the macOS 14 build (packages) and a search of the app (the app build stops at the packages).

| API | Where | Feature |
|---|---|---|
| `Mutex` (Synchronization) | `Packages/SlidePilotRendering/Sources/SlidePilotRendering/PDFFilePresenter.swift:21`, `PDFFileObserver.swift:141`, `Packages/SlidePilotRemoteProtocol/Sources/SlidePilotRemoteProtocol/TrustStore.swift:46` | PDF reload (ADR 0013), remote pairing keys |
| `pointerStyle(_:)` | `SlidePilot/Pointer/PointerOverlay.swift:89,142`, `SlidePilot/Presenter/SlideLinkLayer.swift:58` | Pointer cursors (PTR-*), link cursor |
| `restorationBehavior(_:)` | `SlidePilot/App/SlidePilotApp.swift:81,94` | Presentation and remote windows not restored |
| `defaultWindowPlacement` | `SlidePilot/App/SlidePilotApp.swift:96` | Presentation window on the second screen |
| `Tab(_:systemImage:value:)` | `SlidePilot/Settings/SettingsView.swift:24-36` | Settings window tabs |

`@Observable`, `ContentUnavailableView`, `onKeyPress` and `focusedSceneValue` with optional values need macOS 14; `@Observable` is used for all app state (about 30 files). `@Entry` and `onGeometryChange` are back-deployed. `isolated deinit` compiles for macOS 15 and was not checked at runtime.

## Candidate targets

| Target | Blocking APIs | Fallback | Effort | User-visible loss |
|---|---|---|---|---|
| **macOS 26** (today) | – | – | – | Macs without macOS 26 stay on 1.8. |
| **macOS 15** | Swift Network API, `Observations`, 4 Liquid Glass/toolbar modifiers | Remote only on macOS 26 (`@available` gate, menu item and settings tab hidden); `Observations` replaced by a `withObservationTracking` loop in Core; glass modifiers behind `if #available` | About 2–3 days, plus a CI job on a macOS 15 runner and a manual smoke test in a macOS 15 VM per release | On macOS 15: no remote (neither host nor controller); page field without glass capsule; system look of macOS 15. |
| macOS 15 with remote | as above | Port `RemoteNetwork` to `NWListener`/`NWBrowser`/`NWConnection` (callback API, wrapped in async streams) for macOS 15, keep the Swift API on 26 or use the old API everywhere | About 1–1.5 weeks; a second transport to test, or the newer API dropped | Only the macOS 15 look. |
| **macOS 14** | macOS 15 list, plus `Mutex`, `pointerStyle`, `restorationBehavior`, `defaultWindowPlacement`, `Tab` | `OSAllocatedUnfairLock` or actors; AppKit cursor glue for the pointer and links; `NSWindow.isRestorable` and screen placement in `MacPresentationWindows`; old `tabItem` settings | About 1.5–2 weeks (app build at 14 not completed, more errors likely) | As macOS 15; more AppKit glue against ADR 0010; macOS 14 no longer gets security updates. |
| macOS 13 or older | All of the above, plus Observation | Rewrite all state from `@Observable` to `ObservableObject` | Weeks; a rewrite of the state layer | Not viable. |

## Effects
- **Code structure:** For macOS 15, about 6 availability checks plus one gate around the remote. The rule "no availability checks" in ADR 0001 ends; new code must check the macOS 15 SDK availability (the compiler enforces it). ADR 0010 holds: standard components adapt by themselves, only the hand-picked glass modifiers need a fallback.
- **Tests and CI:** The `macos-26` jobs keep the deployment target honest at compile time. Running on macOS 15 needs an extra job on GitHub's `macos-15` runner (package tests and app tests). The Mac test host and the snapshots run on the maintainer's Mac (macOS 27); the macOS 15 look is only checked by hand, in a VM.
- **Distribution:** App Store and the notarized download use the same minimum (`LSMinimumSystemVersion` from the deployment target). The App Store record is new (ADR 0011), so older systems get no "last compatible version" from the App Store; SlidePilot 1.8 stays the download for them.
- **iPadOS:** stays 26. The remote code paths are shared, so a lower iPadOS target has the same remote problem; not cheap.

## Who would gain
- Hardware: macOS 26 runs on all Apple silicon Macs and a few late Intel Macs. macOS 15 adds Intel Macs from 2018–2019 (MacBook Pro 2018–2019, iMac 2019, iMac Pro, Mac mini 2018). macOS 14 adds the MacBook Air 2018–2019.
- Share: no data for SlidePilot's own users. Public samples from mid-2026 (TelemetryDeck as quoted by third-party sites, Homebrew) put macOS 26 at roughly 60–85 %, macOS 15 at roughly 12–22 % and macOS 14 at about 8 % of Macs. The numbers disagree between sources and are older than the release of macOS 27, so the real share at the 2.0 release is likely lower.
