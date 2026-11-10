# 0008 – GitHub Actions as build feedback for cloud sessions

- Status: Accepted
- Date: 2026-11-10

## Context
Claude Code cloud sessions run on Linux without a Swift/Xcode toolchain. Local sessions on the product owner's Mac have Xcode.

## Decision
- Every PR is built and tested by GitHub Actions on macOS runners (macOS app, iPad simulator, package tests).
- In cloud sessions, CI is the only build and test feedback. A PR is not ready until CI is green.
- Local sessions also run the build and test commands from `CLAUDE.md` before pushing.

## Consequences
- CI must stay fast and reliable. The Xcode version is pinned in the workflow.
- `main` requires the CI status check (ruleset).
