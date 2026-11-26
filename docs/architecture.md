# Architecture

SlidePilot Universal is one SwiftUI app for macOS 26 and iOS/iPadOS 26 (iPad and, from 2.0 on, iPhone including the iPhone Duo, ADR 0015). The decisions behind this document are recorded in [`docs/decisions/`](decisions/). This document describes the target state; sections marked *(Phase 1)* are confirmed or revised after the Phase 1 prototypes.

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
│   ├── SlidePilotRendering/       # PDFKit, render cache, drawing rendering, legacy notes RTF
│   └── SlidePilotRemoteProtocol/  # Codable messages and pairing crypto (2.0)
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
| **SlidePilotCore** | Value-type models: layout configuration, notes position/mode, pointer configuration, drawing model (relative strokes), timer logic (wall-clock based), per-document settings, companion file format and its store (`CompanionStore` actor: one JSON file per PDF, matched by bookmark through `PDFLocator`), the `.slidepilot` export format (`SlidePilotFileFormat`, ADR 0019), legacy notes page format and file names, keyboard command definitions, SlidePilot Pro rules and the trial timer (ADR 0020) | UI frameworks, PDFKit, file system watching |
| **SlidePilotRendering** | PDF loading, page geometry for split notes (half-page rects incl. rotation), render cache actor, thumbnail rendering, drawing rasterization and export into PDF annotations, link and movie annotation extraction (videos stored inside the PDF are written to temporary files through `EmbeddedFileStore` from Core), legacy notes RTF read/write and the RTF pages of the companion notes (RTF needs the AppKit/UIKit attributed-string extensions), watching and reloading the opened PDF (`PDFFileObserver`, it validates new versions with PDFKit) | SwiftUI views, app state |
| **SlidePilotRemoteProtocol** | Codable message types, framing, protocol versioning, pairing, key derivation and encryption, the per-connection state machine `RemoteConnection` (ADR 0017), the `RemoteSession` actor that runs it over any byte stream, and the `TrustStore` protocol | Network sockets and the Keychain (the app owns those) |
| **App target** | SwiftUI scenes and views, `@Observable` state, menus/commands, settings UI, folder access requests, StoreKit 2 (ADR 0020), platform-specific code | Business logic that could be tested in a package |

Logic that can be unit-tested belongs in a package. The app target stays thin.

## Concurrency model (Swift 6, complete strict checking)

- **UI state** is `@Observable` and `@MainActor`. One `PresentationSession` per open document holds the current page, layout, notes, drawing, pointer, curtain and timer state. Both the presenter and the presentation scene observe the same session. The document view registers its session in the app-owned `PresentationRegistry` (Core); the Mac presentation window looks it up by ID, the iPad external display shows the one in the active app window (`PresentationRegistry` tracks the window of each session).
- **Render cache** is an `actor`. It renders off the main actor and returns `Sendable` images (`CGImage`). It never mutates shared `PDFPage` state (see DEF-02 in the parity doc). It counts the bytes of its images itself and renders inside `autoreleasepool`; neighborhood and budgets are in ADR 0005.
- **File observation** (PDF changes on disk) is an `actor` (`PDFFileObserver` in Rendering) fed by an `NSFilePresenter`; it emits new versions through an `AsyncStream` that the `PresentationSession` consumes for as long as the document view lives. Reloads are debounced, read the whole file with coordination, are validated and skipped when the bytes did not change (ADR 0013).
- **Companion file** (notes, per-document settings) is kept by the `CompanionStore` actor in Core; one store serves all windows, so writes never interleave. Each `PresentationSession` owns a `@MainActor` `DocumentCompanion` that loads its entry when the document opens and saves changes about 0.5 s later, when the window closes and when the app leaves the foreground (ADR 0012).
- **Remote** (2.0): every connection runs in a `RemoteSession` actor (RemoteProtocol). It owns the connection's `RemoteConnection` state, reads and writes the byte stream through a `RemoteTransport` and sends all writes through one queue, so encrypted frames never reorder; the protocol logic itself has no I/O (ADR 0017). The app wraps Network framework `NetworkConnection`s as transports and keeps pairing keys in a Keychain `TrustStore`. The `@MainActor` `RemoteService` owns the listener and browser tasks (Bonjour, async Network API) and the UI state; cancelling them ends their sessions. What verified controllers get and may do is decided by the pure `RemoteHostState` (RemoteProtocol); `RemoteService` watches the open sessions with `Observations`, queues each controller's messages in order and renders requested slide images from the render cache off the main actor. Every instance can be presenter and controller (ADR 0015): remote mode is its own window scene with one `@MainActor` `RemoteControl` per window, which runs a controller session to the chosen device, retries it while the window is open, and leaves the decisions (selection, image size, commands, gestures) to the pure `RemoteControllerState` and `RemoteGestureInterpreter` (RemoteProtocol).
- Models crossing isolation boundaries are `Sendable` value types. `@unchecked Sendable` and `nonisolated(unsafe)` need a comment explaining why they are safe.
- No `DispatchQueue` in new code. Use structured concurrency; long-running tasks are cancelled when their owner goes away.

## Scenes and windows

| | macOS | iOS (iPad, iPhone) |
|---|---|---|
| Documents | `DocumentGroup(viewing:)`: open panel, Open Recent, one window per PDF; the app keeps running without windows | `DocumentGroup(viewing:)`: document browser at launch |
| Presenter | The PDF's document window | The PDF's document scene on the device |
| Presentation | `WindowGroup` per document, opened by the presenter: full screen on the second screen if present (opens with the document), or on request with Start Presentation. AppKit glue for screen choice, full screen and screen changes in `MacPresentationWindows`; screen rules in `PresentationScreenPolicy` (Core) | UIKit scene delegate for the external display role (cable or AirPlay), set up by an app delegate adaptor; from iPadOS 27 registered as a scene accessory on each app window (`AppWindowTracker`). Shows the document of the active app window or a ready screen |
| Menus / shortcuts | `Commands` | Same `Commands` (shown with a hardware keyboard) |
| Settings | `Settings` scene | Sheet |

Platform differences are isolated in small files using `#if os(macOS)`. They must not be scattered through shared views.

iPhone and iPad share the iOS column. Layouts adapt to the available size and size classes, never to the device idiom, the orientation or fixed screen sizes: the iPhone Duo shows the compact layout on its outer display and the regular, iPad-like layout on its inner display, and folding keeps the scene and the presentation state (ADR 0015).

## UI principles

Native design first ([ADR 0010](decisions/0010-native-design-first.md)): standard SwiftUI components, SF Symbols, system colors and fonts everywhere. Custom drawing only for the slide surface, the pointer overlay and the drawing layer. The mapping from old custom controls to native components is the "Native replacement" column in the parity doc.

Drawing ([ADR 0016](decisions/0016-drawing-engine.md)): `DocumentDrawings` (Core) is the single source of truth per document, with one undo history per page. Read-only surfaces add `.drawingOverlay(_:page:region:)` on top of a `SlideSurface`; further layers such as the pointer stack as more overlays above it, and the presentation's curtain covers them all. The editable layer is an `NSView` on the Mac and a `PKCanvasView` on iPad; both are first responder in draw mode and provide the drawing's own `UndoManager`. On iPad the model's strokes are drawn below the canvas; PencilKit only shows the stroke in progress. With "Save drawings" on, `SavedDrawingsModifier` (app) keeps the drawings in the companion file.

## Persistence

| Data | Storage |
|---|---|
| Notes, drawings, per-document settings | One **companion file** per PDF (format defined in Core, versioned) in the **app container**, matched to the PDF by bookmark (ADR 0012). Entries that hold only settings expire 12 months after last open (SET-03); entries with notes or drawings do not expire |
| Legacy notes `<pdf>-notes.rtf` | Imported on open (macOS, after a folder grant) or with Import Notes… (iPad); RTF export stays available |
| Global preferences (layout, pointer, awake, crossfade, save drawings, time size) | `UserDefaults` through one typed settings store: `AppSettings` (Core, `@MainActor @Observable`) with an injectable `SettingsStore`; one instance per app, passed to the scenes through the environment |
| Access to PDFs and neighbouring files | Security-scoped bookmarks. Folder access is requested only when needed (videos, `run:` links, legacy notes on macOS) and stored as a bookmark (ADR 0012). Videos stored inside the PDF need none: they are copied to the app's temporary folder for as long as the document is open |
| Trusted remote devices (2.0) | Keychain |

## Product configuration

- Bundle identifier, team and version come from `Config/*.xcconfig`. No code assumes a specific bundle ID. That keeps a later split into two App Store apps (free Mac, paid iPad) possible.
- Features that differ between products (e.g. the donation hint, free Mac download only, ADR 0011) are behind a compile-time flag set in the xcconfig, not behind `#if os(...)`.
- **SlidePilot Pro (ADR 0020):** the App Store build is free; the in-app purchase SlidePilot Pro lifts the 3-minute trial of audience output and remote control. The rules (Pro status, what is limited, the trial timer with an injectable clock) live in SlidePilotCore and are tested without StoreKit: `ProStatus` (unknown, locked, unlocked, unlimited for the free download), `LimitedFeature`, the value type `TrialSession` and the `@MainActor` `TrialCoordinator` that the app owns once per audience output or remote connection and drives with `run()` in the output's task. StoreKit 2 lives only in the app target, in `ProStore` (`SlidePilot/Pro/ProStore.swift`): one `@MainActor @Observable` instance owned by the app (iPad and iPhone: the app delegate, so the external display reads it too) and passed through the environment. It listens to `Transaction.updates` from launch, derives the status from `Transaction.currentEntitlements` with the Core rule `ProStatus(entitlements:productID:)` (revoked or refunded purchases lock, Family Sharing counts) and offers `purchase()` and `restore()`. In the free Mac download (`SLIDEPILOT_FREE_DOWNLOAD`) the same file compiles a stub without StoreKit whose status is always unlimited. The product ID is the build setting `SLIDEPILOT_PRO_PRODUCT_ID` in `Config/Shared.xcconfig` (empty in `FreeDownload.xcconfig`), read through the Info.plist key `SlidePilotProProductID`. `Config/SlidePilot.storekit` (not bundled) lets the `SlidePilot` scheme's run action buy it locally. Each instance checks only its own Pro status; the remote protocol carries none. Remote connections use `RemoteTrialBook` and its `@MainActor` runner `RemoteTrials` (Core) instead of one coordinator per connection, because a trial belongs to the other device across automatic reconnects: `RemoteControl` keeps one per remote mode window, `RemoteService` one for all controllers of this host (PRO-04).

## Testing

- Swift Testing (`import Testing`) in every package and for app logic.
- Packages are tested with `swift test` and as part of the app's test plan.
- Shared sample documents live in `Fixtures/` (see its README). The compiled PDFs are committed because CI has no LaTeX. They are not part of the app bundle. Package tests run unhosted on the Mac and in the simulator, so they read fixtures from the source tree through `#filePath` (see `LegacyNotesRTFTests`).
- CI tests on the Mac only (packages and the macOS test plan). For iOS it only builds the app (`generic/platform=iOS Simulator`), so iOS-only code cannot break unnoticed; it boots no simulator and runs no tests, because the test plan holds only package tests, which do not depend on the platform beyond a few `#if os` branches (ADR 0008). iPad and iPhone share the `iphonesimulator` SDK and binary, so one build covers both. Behavior on iPad and iPhone, including compact width and height, is checked by Claude in the simulators. Revisit this when app-hosted UI tests are added.
- UI behavior is checked by Claude in the iPad and iPhone simulators and, on the Mac, through the SlidePilot Test Host, which captures and drives only the test build (ADR 0018). The "How to verify" steps in each PR cover only what that cannot reach. UI tests are added only where they pay off.
