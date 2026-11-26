# 0008 – GitHub Actions as build feedback for cloud sessions

- Status: Accepted
- Date: 2026-11-10

## Context
Claude Code cloud sessions run on Linux without a Swift/Xcode toolchain. Local sessions on the product owner's Mac have Xcode.

## Decision
- Every PR is built and tested by GitHub Actions on macOS runners (macOS app, iPad simulator, package tests).
  - Amendment (2026-11-12): PRs that only change documentation, Claude configuration or issue/PR templates skip the macOS runner jobs. The required check `ci-success` still runs and passes. Any path not on that list, and every push to `main`, runs the full pipeline.
  - Amendment (2026-11-26): iOS is only built (`generic/platform=iOS Simulator`), not tested in a simulator. Booting the simulator made the iPad job take up to 15 minutes and the slowest part of every PR, while its tests were the package tests the Mac jobs already run; in all runs so far it caught one flaky test and no app defect. The build still catches iOS-only compile errors, which cloud sessions cannot see otherwise. iOS tests run in local sessions.
- In cloud sessions, CI is the only build and test feedback. A PR is not ready until CI is green.
- Local sessions also run the build and test commands from `CLAUDE.md` before pushing.

## Consequences
- CI must stay fast and reliable. The Xcode version is pinned in the workflow.
- `main` requires the CI status check (ruleset).
