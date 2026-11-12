# 0003 – App Store distribution

- Status: Superseded by [0011](0011-universal-purchase-and-direct-download.md)
- Date: 2026-11-10

## Context
SlidePilot 1.8 was distributed as an unsigned download with Sparkle updates and a donation alert. The new app ships on the Mac App Store and the iPad App Store.

## Decision
- Distribution only through the App Store. The Mac app is free, the iPad app is paid.
- The pricing model (one universal purchase vs. **two separate App Store apps**, current leaning) is decided before Phase 5.
- Sparkle is not used. The app is sandboxed.
- The donation hint stays in the **free Mac app only**, in an App-Store-compliant form (e.g. an In-App Purchase tip jar or a neutral hint). It never appears in the paid iPad app. The form is decided before Phase 5.

## Consequences
- Bundle ID, team and product flags live in xcconfig files; nothing hard-codes a single bundle ID.
- The real bundle ID prefix and development team are **not committed** (public repository). They live in a git-ignored `Config/Local.xcconfig`; the repository contains only a template with placeholders. CI builds with a neutral placeholder bundle ID and without code signing.
- Product differences use a compile-time flag (e.g. `SLIDEPILOT_FREE_EDITION`), so a second app target can be added later without code changes.
- Sandbox requirements shape file access (ADR 0007).
