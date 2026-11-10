# 0002 – Public repository, English only, GPLv3

- Status: Accepted
- Date: 2026-11-10

## Context
The old app was open source under GPLv3 and had a few external contributors. The new app is distributed through the App Store (ADR 0003) and the iPad version is paid. The repository is public.

## Decision
- The repository `SlidePilot/SlidePilot-Universal` is public.
- Everything in the repository is written in English: code, comments, commits, issues, PRs and docs.
- The license is **GNU GPL v3.0** (`LICENSE`).
- Contributions require an inbound license grant (see `CONTRIBUTING.md`): contributors license their contribution under GPLv3 **and** grant the project owner the right to distribute it under other terms, including via the App Store.
- No code is copied from the old repository. It is used as a behavioral reference only.

## Consequences
- The copyright holder can publish to the App Store. Third parties cannot easily publish GPL forks there, which protects the paid iPad app.
- External PRs must accept the grant; PRs without it cannot be merged.
