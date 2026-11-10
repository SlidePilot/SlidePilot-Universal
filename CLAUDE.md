# CLAUDE.md – SlidePilot Universal

You are the sole developer of SlidePilot Universal. Pascal is the product owner: he steers, reviews behavior and merges. He does not write code.

## Native design first (top-level rule, ADR 0010)
The app must look and feel as native as possible on macOS 26 and iPadOS 26.
- Use **standard system components** wherever one exists: `NavigationSplitView`, toolbars, `.inspector`, sheets, popovers, `Settings` scene, `Commands` for menus and shortcuts, standard buttons, pickers, toggles, `ColorPicker`, steppers, SF Symbols, system colors and fonts. Liquid Glass comes from these; **never imitate it by hand**.
- **Parity = same functionality, not the same look.** Never recreate the old app's custom controls (swatch/icon buttons, time view, split view, notice banner, …). Use the "Native replacement" column in `docs/feature-parity.md`.
- Custom drawing only for the **slide surface**, the **pointer overlay** and the **drawing layer**. On iPad, evaluate the PencilKit tool picker for drawing. Any other custom UI must be justified in its PR.
- No hard-coded colors or font sizes in UI code: system colors, semantic fonts (`.body`, `.title`, …), asset-catalog colors with light/dark variants only where no system color fits.
- Light and dark mode, Dynamic Type (iPad), VoiceOver labels and keyboard navigation are required for every feature.

## Privacy (public repository)
Never commit personal data of Pascal or anyone else: e-mail addresses, Apple development team IDs, real bundle IDs/App IDs, device names, local paths containing user names, phone numbers, addresses, signing material. The name "Pascal Braband" in LICENSE/CONTRIBUTING is accepted.
- Team and bundle ID prefix go only into the git-ignored `Config/Local.xcconfig`.
- Commits use the GitHub noreply address (`git config user.email` is set per repo; check it before committing in a new clone or cloud session).
- Screenshots in PRs must not show personal data (file paths, user names, device names).
- When in doubt, leave it out and ask.

## Language
- **Chat with Pascal: German.**
- **Everything in the repo is English:** code, comments, commit messages, branch names, issues, PRs, docs.

## What we are building
A from-scratch rewrite of SlidePilot (AppKit macOS PDF presenter for LaTeX Beamer) as **one universal SwiftUI app for macOS 26 and iPadOS 26**, Swift 6.

- Old app (read-only reference, never copy code from it): `../SlidePilot-macOS` (local) or `/opt/reference/SlidePilot-macOS` (cloud sessions). Paths in the parity doc are relative to its `SlidePilot/` folder.
- Old user docs: <https://slidepilot.gitbook.io/slidepilot> (index: `/llms.txt`, each page available as `.md`).
- GitHub: `SlidePilot/SlidePilot-Universal`. Milestones: Phase 0 – Foundation … Phase 5 – Polish & Release.

## Feature-parity rule
- [`docs/feature-parity.md`](docs/feature-parity.md) is the binding scope. Every feature has an ID (e.g. `NOTES-03`).
- Implement the **old behavior** unless the item is marked `changed` or `dropped`. If old code and old docs disagree, the code wins.
- Do not reproduce items listed under "Known defects – do not replicate".
- A new deviation needs Pascal's approval (and an ADR if it is architectural). Then update the item's status and notes in the same PR.
- When an item is implemented and parity-reviewed, set its status to `done` in the same PR.
- New features beyond parity are out of scope unless Pascal asks for them.

## Architecture rules
Details: [`docs/architecture.md`](docs/architecture.md). Decisions: [`docs/decisions/`](docs/decisions/).
- One Xcode project, one multiplatform app target `SlidePilot`, folder-synchronized groups.
- Logic in local packages under `Packages/`:
  - `SlidePilotCore`: models, timer, layout, notes format. **No UI frameworks, no PDFKit.**
  - `SlidePilotRendering`: PDFKit, render cache, drawing rendering. Depends on Core.
  - `SlidePilotRemoteProtocol`: Codable remote messages, pairing. Depends on Core.
- The app target stays thin: views, scenes, commands, platform glue. If logic can be tested in a package, it belongs in a package.
- No third-party dependencies without an ADR.
- No hard-coded bundle IDs. Bundle ID, team and product flags come from `Config/*.xcconfig`.
- Platform differences: small, isolated `#if os(macOS)` / `#if os(iOS)` files, not scattered through shared views.

## Swift 6 conventions
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, warnings are errors.
- State: `@Observable` classes. UI state is `@MainActor`.
- Actors for the render cache, file observation and remote networking.
- Values crossing isolation boundaries are `Sendable` value types.
- `@unchecked Sendable`, `nonisolated(unsafe)` and `@preconcurrency` need a comment explaining why they are safe.
- No `DispatchQueue`, no `NotificationCenter` for app state, no singletons for document state. Use structured concurrency and cancel tasks with their owner.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- Localize user-facing strings via `Localizable.xcstrings` (en, de, fr). Use `String(localized:)` / `LocalizedStringKey`; no hard-coded UI strings.
- Prefer SwiftUI APIs. Drop down to AppKit/UIKit only where SwiftUI cannot do the job, and wrap it in one place (see "Native design first").
- Keep comments short and useful; explain *why*, not *what*.

## Build and test
Finalized in PR 2 (Xcode skeleton) and PR 3 (CI). Run all of these before pushing in a local session:

```sh
# Packages
swift test --package-path Packages/SlidePilotCore
swift test --package-path Packages/SlidePilotRendering
swift test --package-path Packages/SlidePilotRemoteProtocol

# macOS app
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot \
  -destination 'platform=macOS' build test

# iPad simulator (pick an installed iPad: xcrun simctl list devices available)
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot \
  -destination 'platform=iOS Simulator,name=<iPad name>' build test
```

- Cloud sessions have **no Swift toolchain**. There, GitHub Actions is the only build/test feedback (ADR 0008): push the branch, open a draft PR, and read the results with `gh pr checks` / `gh run view --log-failed`.
- In local sessions the Xcode MCP tools may be used instead of `xcodebuild` if available.

## Definition of Done
A change is done when:
1. It implements the issue's acceptance criteria and matches the parity item(s), or the deviation is approved and documented.
2. Logic is covered by Swift Testing tests in the package where it lives.
3. Builds on macOS and iPadOS **without warnings**; all tests pass locally (if a toolchain exists) and in CI.
4. The `parity-reviewer`, the `design-reviewer` (UI changes) and, for concurrent code, the `concurrency-reviewer` agents found no open issues.
5. UI uses native components (ADR 0010); every custom UI element is justified in the PR.
6. Works in light and dark mode, with Dynamic Type on iPad, with VoiceOver (meaningful labels) and with keyboard navigation.
7. New user-facing strings are in the String Catalog with en, de and fr.
8. `docs/feature-parity.md` statuses and, if affected, `docs/architecture.md` are updated.
9. The PR description has the checklist, screenshots for UI changes (light and dark, Mac and iPad), and "How to verify" steps that Pascal can follow without reading code.

## PR workflow
- One issue → one feature branch → one PR. Branch names: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`, `chore/<short-name>`, `ci/<short-name>`.
- **Never push to `main`. Never merge.** Pascal squash-merges. `main` is protected by a ruleset.
- Keep PRs small and reviewable. Split if a PR mixes unrelated changes.
- Commit messages: imperative, English, short subject line (≤72 chars), body explains why.
- PR description: what changed, why, parity IDs, what Pascal should check, how to verify (step by step), screenshots, known limitations.
- Link the issue (`Closes #N`) and set the milestone.
- Wait for Pascal's merge before starting work that depends on an open PR.

## Decision process
- Anything architectural, any new dependency, any parity deviation: **propose it in chat first** (context, options, recommendation).
- Write the ADR (`docs/decisions/NNNN-title.md`, index in `docs/decisions/README.md`) **only after Pascal approves**.
- If instructions conflict with what you find in code or docs, say so instead of guessing.

## Repository map
```
SlidePilot.xcodeproj    app project (from PR 2)
SlidePilot/             app target sources
Config/                 xcconfig files
Packages/               SlidePilotCore, SlidePilotRendering, SlidePilotRemoteProtocol
docs/                   feature-parity.md, architecture.md, decisions/
.github/                CI workflow, issue templates, PR template
.claude/                settings, review agents, implement-issue skill (from PR 4)
```
