# Architecture

SlidePilot Universal is one SwiftUI app for macOS 26 and iPadOS 26. The decisions behind this document are recorded in [`docs/decisions/`](decisions/). This document describes the target state; sections marked *(Phase 1)* are confirmed or revised after the Phase 1 prototypes.

## Repository layout

```
SlidePilot-Universal/
├── SlidePilot.xcodeproj           # one project, one multiplatform app target
├── SlidePilot.xctestplan          # test plan: all package test targets
├── SlidePilot/                    # app target (folder-synchronized group)
│   ├── App/                       # @main App, scenes, commands (menus)
│   ├── Presenter/                 # presenter UI
│   ├── Presentation/              # audience UI (window / external display)
│   ├── Settings/
│   └── Resources/                 # Assets.xcassets, Localizable.xcstrings
├── Config/                        # xcconfig files (bundle ID, team, versions)
├── Packages/
│   ├── SlidePilotCore/            # models and logic, no UI, no PDFKit
│   ├── SlidePilotRendering/       # PDFKit, render cache, drawing rendering
│   └── SlidePilotRemoteProtocol/  # Codable messages and pairing crypto (1.1)
├── Fixtures/                      # sample Beamer PDFs (+ .tex sources), legacy notes file, test video
├── docs/
└── .github/workflows/ci.yml
```

## Modules and dependencies

```
SlidePilot (app)
 ├── SlidePilotRendering ──► SlidePilotCore
 ├── SlidePilotRemoteProtocol ──► SlidePilotCore
 └── SlidePilotCore
```

Dependencies only point downward. Core never imports SwiftUI, AppKit, UIKit or PDFKit.

| Module | Contents | Must not contain |
|---|---|---|
| **SlidePilotCore** | Value-type models: layout configuration, notes position/mode, pointer configuration, drawing model (relative strokes), timer logic (wall-clock based), per-document settings, companion file format, legacy notes RTF import/export parser, keyboard command definitions | UI frameworks, PDFKit, file system watching |
| **SlidePilotRendering** | PDF loading, page geometry for split notes (half-page rects incl. rotation), render cache actor, thumbnail rendering, drawing rasterization and export into PDF annotations, link and movie annotation extraction | SwiftUI views, app state |
| **SlidePilotRemoteProtocol** | Codable message types, protocol versioning, pairing and key derivation | Network sockets (the app owns those) |
| **App target** | SwiftUI scenes and views, `@Observable` state, menus/commands, settings UI, file access (bookmarks, file presenters), platform-specific code | Business logic that could be tested in a package |

Logic that can be unit-tested belongs in a package. The app target stays thin.

## Concurrency model (Swift 6, complete strict checking)

- **UI state** is `@Observable` and `@MainActor`. One `PresentationSession` per open document holds the current page, layout, notes, drawing, pointer, curtain and timer state. Both the presenter and the presentation scene observe the same session.
- **Render cache** is an `actor`. It renders off the main actor and returns `Sendable` images (`CGImage`). It never mutates shared `PDFPage` state (see DEF-02 in the parity doc).
- **File observation** (PDF changes on disk) is an `actor` that emits changes through an `AsyncStream`.
- **Remote** (1.1) is an `actor` owning the `NWListener`/`NWConnection`s.
- Models crossing isolation boundaries are `Sendable` value types. `@unchecked Sendable` and `nonisolated(unsafe)` need a comment explaining why they are safe.
- No `DispatchQueue` in new code. Use structured concurrency; long-running tasks are cancelled when their owner goes away.

## Scenes and windows

| | macOS | iPadOS |
|---|---|---|
| Presenter | Main `WindowGroup` window | Main scene on the device |
| Presentation | Second window, full screen on the second screen if present | Scene on the external display (`UIWindowScene` external display role) *(Phase 1)* |
| Menus / shortcuts | `Commands` | Same `Commands` (shown with a hardware keyboard) |
| Settings | `Settings` scene | Sheet |

Platform differences are isolated in small files using `#if os(macOS)`. They must not be scattered through shared views.

## UI principles

Native design first ([ADR 0010](decisions/0010-native-design-first.md)): standard SwiftUI components, SF Symbols, system colors and fonts everywhere. Custom drawing only for the slide surface, the pointer overlay and the drawing layer. The mapping from old custom controls to native components is the "Native replacement" column in the parity doc.

## Persistence

| Data | Storage |
|---|---|
| Notes, drawings, per-document settings | One **companion file** per PDF (format defined in Core, versioned). The location is decided in Phase 1 (next to the PDF vs. app container keyed by bookmark), depending on sandbox and iPad file access. Entries in the app container expire 28 days after last open |
| Legacy notes `<pdf>-notes.rtf` | Imported automatically on open; RTF export stays available |
| Global preferences (layout, pointer, awake, crossfade, save drawings, time size) | `UserDefaults` through one typed settings store |
| Access to PDFs and neighbouring files | Security-scoped bookmarks |
| Trusted remote devices (1.1) | Keychain |

## Product configuration

- Bundle identifier, team and version come from `Config/*.xcconfig`. No code assumes a specific bundle ID. That keeps a later split into two App Store apps (free Mac, paid iPad) possible.
- Features that differ between products (e.g. the donation hint, free Mac download only, ADR 0011) are behind a compile-time flag set in the xcconfig, not behind `#if os(...)`.

## Testing

- Swift Testing (`import Testing`) in every package and for app logic.
- Packages are tested with `swift test` and as part of the app's test plan.
- Shared sample documents live in `Fixtures/` (see its README). The compiled PDFs are committed because CI has no LaTeX. They are not part of the app bundle; how tests load them is decided with the first test that needs them.
- UI behavior is verified manually with the "How to verify" steps in each PR. UI tests are added only where they pay off.
