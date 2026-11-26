# 0008 – GitHub Actions as build feedback for cloud sessions

- Status: Accepted
- Date: 2026-11-10

## Context
Claude Code cloud sessions run on Linux without a Swift/Xcode toolchain. Local sessions on the product owner's Mac have Xcode.

## Decision
- Every PR is built and tested by GitHub Actions on macOS runners (macOS app, iPad simulator, package tests).
  - Amendment (2026-11-12): PRs that only change documentation, Claude configuration or issue/PR templates skip the macOS runner jobs. The required check `ci-success` still runs and passes. Any path not on that list, and every push to `main`, runs the full pipeline.
  - Amendment (2026-11-26): PRs should be green in minutes, so CI builds and tests only what can break in a PR:
    - iOS is only built (`generic/platform=iOS Simulator`), not tested in a simulator. Booting the simulator made the iPad job take up to 15 minutes, while its tests were the package tests the Mac jobs already run; in all runs so far it caught one flaky test and no app defect. The build still catches iOS-only compile errors, which cloud sessions cannot see otherwise.
    - The macOS job only builds the app. Its tests were the same package tests the packages job runs with `swift test`. Once app-hosted tests exist, they move back into this job.
    - The free Mac download, the Mac snapshots and the test host are built on `main`, on manual runs and on PRs that touch them or the build configuration.
    - The package tests run on iOS in the workflow "iOS tests": weekly, manually before each release ([`release.md`](../release.md)) and on PRs that change it. A failed scheduled or manual run opens an issue, so the failure reaches the maintainer. Local sessions still run them before every push.
- In cloud sessions, CI is the only build and test feedback. A PR is not ready until CI is green.
- Local sessions also run the build and test commands from `CLAUDE.md` before pushing.

## Consequences
- CI must stay fast and reliable. The Xcode version is pinned in the workflow.
- `main` requires the CI status check (ruleset).
