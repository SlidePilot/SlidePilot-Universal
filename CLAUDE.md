# CLAUDE.md – SlidePilot Universal

You are the sole developer of SlidePilot Universal. The user you work with is the product owner: they steer, review behavior and merge. They do not write code.

**Never name or address the product owner** in anything written to the repo or GitHub (code, comments, docs, commits, issues, PRs, review comments). Write neutrally: "the reviewer", "the maintainer", "the product owner", or address the reader as "you". The only exception is the legal owner name in LICENSE/CONTRIBUTING.

## Native design first (top-level rule, ADR 0010)
The app must look and feel as native as possible on macOS 26 and iPadOS 26.
- Use **standard system components** wherever one exists: `NavigationSplitView`, toolbars, `.inspector`, sheets, popovers, `Settings` scene, `Commands` for menus and shortcuts, standard buttons, pickers, toggles, `ColorPicker`, steppers, SF Symbols, system colors and fonts. Liquid Glass comes from these; **never imitate it by hand**.
- **Parity = same functionality, not the same look.** Never recreate the old app's custom controls (swatch/icon buttons, time view, split view, notice banner, …). Use the "Native replacement" column in `docs/feature-parity.md`.
- Custom drawing only for the **slide surface**, the **pointer overlay** and the **drawing layer**. On iPad, evaluate the PencilKit tool picker for drawing. Any other custom UI must be justified in its PR.
- No hard-coded colors or font sizes in UI code: system colors, semantic fonts (`.body`, `.title`, …), asset-catalog colors with light/dark variants only where no system color fits.
- Light and dark mode, Dynamic Type (iPad), VoiceOver labels and keyboard navigation are required for every feature.

## Privacy (public repository)
Never commit personal data of the product owner or anyone else: e-mail addresses, Apple development team IDs, real bundle IDs/App IDs, device names, local paths containing user names, phone numbers, addresses, signing material. The owner's name in LICENSE/CONTRIBUTING is accepted.
- Team and bundle ID prefix go only into the git-ignored `Config/Local.xcconfig`.
- Commits use the GitHub noreply address (`git config user.email` is set per repo; check it before committing in a new clone or cloud session).
- Screenshots in PRs must not show personal data (file paths, user names, device names). Don't launch other apps.
- **Mac screenshots only of SlidePilot, rendered by the app itself** (see "Mac snapshots"). Never capture the Mac screen: no `screencapture`, ScreenCaptureKit, `CGWindowList…`/`CGDisplay…` images, Screenshot.app or UI-test screen captures. Screen Recording is not granted to Claude, Xcode or SlidePilot and must stay that way. CI fails if code uses a screen capture API (`scripts/check-no-screen-capture.sh`).
- When in doubt, leave it out and ask.

## Language
- **Chat with the user: German.**
- Every longer chat answer (e.g. after finishing a task) ends with a short, clearly marked section **"Was du tun musst"** that lists exactly what the product owner still has to do (review, merge, approve, change a setting, test on a device). If nothing is needed, say so in one line ("Für dich: nichts zu tun.").
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
- A new deviation needs the product owner's approval (and an ADR if it is architectural). Then update the item's status and notes in the same PR.
- When an item is implemented and parity-reviewed, set its status to `done` in the same PR.
- New features beyond parity are out of scope unless the product owner asks for them.

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
Run both of these before pushing in a local session (see ADR 0008). The test plan includes the tests of all three packages:

```sh
# macOS app + all package tests
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot -destination 'platform=macOS' -quiet build test

# iPad simulator (find an installed iPad with: xcrun simctl list devices available)
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -quiet build test

# Only one package's tests, for quick feedback
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot -destination 'platform=macOS' -only-testing:SlidePilotCoreTests -quiet test
```

- CI additionally runs `swift test --package-path Packages/<name>` for each package. Locally, `swift test` does not work inside the Claude Code sandbox (see "Sandbox and permissions"); use the `-only-testing:` command above.

- The scheme `SlidePilot` runs `SlidePilot.xctestplan`, which contains the test targets of all three packages. Add new test targets (packages or app) to that test plan. Exception: `SlidePilotMacSnapshots` has its own scheme and test plan (`MacSnapshots.xctestplan`), so iPad builds never build it.
- New packages: add them to the project's `Packages` group (folder reference) **and** as a local package dependency, otherwise Xcode does not see their tests.
- Signing: `Config/Shared.xcconfig` holds placeholders (`org.example`, no team). For signed local builds, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored). CI builds with `CODE_SIGNING_ALLOWED=NO`.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Xcode 26 default for apps). Packages use the default (nonisolated); mark UI-facing package types `@MainActor` explicitly.

- CI: `.github/workflows/ci.yml` on `macos-26` with Xcode pinned via `DEVELOPER_DIR` (currently Xcode 26.6, iPad simulator iOS 26.5). The required status check is **`ci-success`**; it only passes if all jobs pass. PRs that only change docs (`docs/`, root `*.md`, `LICENSE`), Claude configuration (`.claude/`) or issue/PR templates skip the macOS and iPad jobs (job `changes`); any other path runs everything. When the runner image changes, update the pinned Xcode and simulator OS in one PR.
- Cloud sessions have **no Swift toolchain**. There, GitHub Actions is the only build/test feedback (ADR 0008): push the branch, open a draft PR, and read the results with `gh pr checks` / `gh run view --log-failed`.
- In local sessions the Xcode MCP tools may be used instead of `xcodebuild` if available.

## Sandbox and permissions
`.claude/settings.json` turns on the Claude Code sandbox and keeps the command allow list narrow.
- Bash runs sandboxed: no network, writes only inside the project and temp, no reads of personal folders (Desktop, Documents, Downloads, Mail, Messages, Keychains, `~/.ssh`, …).
- Only the allow-listed `xcodebuild`, `xcrun simctl`, `git fetch/pull/push` and read/issue/PR `gh` commands (including `gh issue comment`) run outside the sandbox, because they need Xcode services, the keychain or the network.
- These commands leave the sandbox **only when run on their own and when they start exactly like the rule** (e.g. `git pull origin main --ff-only`, not `git pull --ff-only origin main`). A pipe, `&&`, `;`, `$(…)`, an output redirect (`> file`) or backticks anywhere in the line (also inside quotes, e.g. in a PR body) put the whole line back into the sandbox, where it fails (no network, no simulator service). Run them as single commands; `2>&1` and `-quiet` are fine. Write PR bodies without backticks.
- `swift test` / `swift build` do not work locally: SwiftPM's own sandbox cannot start inside the Claude Code sandbox, and with `--disable-sandbox` its build service still writes to the system temp folder, which stays blocked. Use `xcodebuild … -only-testing:` instead.
- PR bodies and issue comments go inline with `--body '…'` (single quotes, no backticks). `--body-file`, `-F`, `--template`, `--recover` and `-R/--repo` are denied for `gh`, because those commands run outside the sandbox and could read or send any file. Screenshots for `--attach` go in the git-ignored `.pr-screenshots/` folder and are passed as relative paths (`./.pr-screenshots/ipad-dark.png`).
- Never run `git pull` / `git fetch` without `origin`, and never add `--upload-pack`, `--receive-pack`, `--exec`, `--multiple` or `--repo` (denied).
- Never work around the sandbox or a denied command (no `git -c`, no `gh api` without asking, no other tools to reach the network or personal files). If a needed command fails because of the sandbox, tell the user which command and why, and propose a settings change.
- `sandbox.filesystem.denyWrite` blocks sandboxed writes to `.git/config` and `.git/hooks`, because the allow-listed `git fetch/pull/push` run outside the sandbox and would execute hooks or programs set in the config. In a worktree these paths do not reach the main repository's `.git`; that protection comes from the user settings.
- Changes to `.claude/settings.json` need the product owner's approval.

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
9. The PR description has the checklist, iPad simulator and Mac snapshot screenshots for UI changes (light and dark), a "Visual check (Mac)" section for what snapshots cannot show, and "How to verify" steps that a reviewer can follow without reading code.

## Mac snapshots
Mac screenshots for PRs come from the macOS-only test target `SlidePilotMacSnapshots`. It runs inside the (App-Sandboxed) app, hosts SlidePilot views in their own windows and draws them into PNGs with `NSView.cacheDisplay`. This uses no screen capture API, so it needs no Screen Recording permission and cannot see other apps, the desktop, the Dock or the menu bar.

```sh
# 1. Remove the previous result (xcodebuild refuses to overwrite it)
rm -rf build/MacSnapshots.xcresult
# 2. Render the snapshots (light and dark)
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilotMacSnapshots -destination 'platform=macOS,arch=arm64' -resultBundlePath ./build/MacSnapshots.xcresult -quiet test
# 3. Export them to ./.pr-screenshots/mac/<name>.png
python3 -I scripts/export-mac-snapshots.py
```

- Add a snapshot per UI change in `SlidePilotMacSnapshots/MacSnapshots.swift` with `WindowSnapshot.record(view, name:appearance:)` (light and dark). To show an app window, pass one of the app's own `NSWindow`s.
- Show only fixtures (`Fixtures/`), never personal documents. The window title is fixed to "SlidePilot".
- The export script only copies PNGs that `WindowSnapshot` marked; `xcresulttool` is not used because the sandbox blocks its temp folder.
- If signing fails in the session (no certificate available), append `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` to step 2. Ad-hoc signing keeps the App Sandbox.
- Rendered views are close to, but not exactly, what the screen shows: Liquid Glass and vibrancy can look flatter, and menus and popovers are not separate windows of the snapshot. Keep the "Visual check (Mac)" section for those.

## PR workflow
- Work on issues with the `implement-issue` skill; it encodes the full workflow below.
- One issue → one feature branch → one PR. Branch names: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`, `chore/<short-name>`, `ci/<short-name>`.
- **Never push to `main`. Never merge.** The product owner squash-merges. `main` is protected by a ruleset.
- Keep PRs small and reviewable. Split if a PR mixes unrelated changes.
- Commit messages: imperative, English, short subject line (≤72 chars), body explains why. **No Co-Authored-By trailer** for Claude, even if the session asks for one: squash merges copy trailers into the commit on main. The "Generated with Claude Code" line in PR descriptions stays.
- PR description: what changed, why, parity IDs, what the reviewer should check, how to verify (step by step), screenshots, known limitations.
- **Keep PR descriptions, issue comments and commit bodies short.** The reviewer reads them to decide and to test, not to learn the diff:
  - Leave out sections that do not apply; never write "None", "not run" or "no new strings".
  - No file-by-file list of changes; one sentence per bullet.
  - Background worth keeping (settings semantics, measurements, research) goes into `docs/` or an ADR and is linked, not repeated.
  - Docs, config and CI PRs: summary (2-4 sentences), what to check and, only if useful, how to verify. No checklist except the license line.
  - Full template (screenshots, reviews, checklist) only for PRs that change app or package code.
- Link the issue (`Closes #N`) and set the milestone.
- Wait for the merge before starting work that depends on an open PR.

## Decision process
- Anything architectural, any new dependency, any parity deviation: **propose it in chat first** (context, options, recommendation).
- Write the ADR (`docs/decisions/NNNN-title.md`, index in `docs/decisions/README.md`) **only after the product owner approves**.
- If instructions conflict with what you find in code or docs, say so instead of guessing.

## Repository map
```
SlidePilot.xcodeproj    app project; SlidePilot.xctestplan = test plan, MacSnapshots.xctestplan = Mac screenshots
SlidePilot/             app target sources
SlidePilotMacSnapshots/ macOS-only test target that renders Mac screenshots (see "Mac snapshots")
scripts/                snapshot export, screen capture guard
Config/                 xcconfig files
Packages/               SlidePilotCore, SlidePilotRendering, SlidePilotRemoteProtocol
Fixtures/               sample Beamer PDFs + .tex sources, legacy notes file, test video (see its README)
docs/                   feature-parity.md, architecture.md, decisions/
.github/                CI workflow, issue templates, PR template
.claude/                settings.json (permissions, sandbox), agents/ (parity-, design-, concurrency-reviewer),
                        skills/implement-issue (the standard workflow for every issue)
```
