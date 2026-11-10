# 0004 – Architecture: one project, multiplatform target, local packages

- Status: Accepted
- Date: 2026-11-10

## Context
The old app used AppKit singletons that communicated through NotificationCenter. Logic and UI were mixed, which made it hard to test and impossible to share with iPad.

## Decision
- One Xcode project with one multiplatform app target `SlidePilot` (macOS + iPadOS) using folder-synchronized groups.
- Logic lives in local Swift packages:
  - **SlidePilotCore**: models, timer, layout, notes format. No UI.
  - **SlidePilotRendering**: PDFKit, render cache, drawing rendering.
  - **SlidePilotRemoteProtocol**: remote messages and pairing.
- Swift 6 language mode with complete strict concurrency checking.
- `@Observable` for state; UI state is `@MainActor`. Actors for the render cache, file observation and remote.
- No third-party dependencies unless clearly needed; adding one requires an ADR.

## Consequences
- Packages are testable with `swift test` without the app.
- Details: [`docs/architecture.md`](../architecture.md).
