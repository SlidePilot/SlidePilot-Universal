# 0001 – Minimum OS: macOS 26 and iPadOS 26

- Status: Accepted
- Date: 2026-11-10

## Context
The rewrite targets one universal SwiftUI app. Older OS versions would need fallbacks for SwiftUI, Observation and window/scene APIs, and would need more testing.

## Decision
The deployment target is **macOS 26.0** and **iPadOS 26.0**. iPhone is not a target of the main app. The iPhone remote app is a separate target later (ADR 0006).

## Consequences
- We can use current SwiftUI, `@Observable`, Swift Testing and the latest scene APIs without availability checks.
- Users on older macOS versions stay on SlidePilot 1.8 (distributed outside the App Store).
- The local toolchain is Xcode 27.x with newer SDKs. The deployment target stays 26.0, and CI also builds against 26.0.
