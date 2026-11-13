---
name: implement-issue
description: Implement a GitHub issue of SlidePilot Universal end to end - read the issue, study the old app's code and docs, plan, write tests, implement, build and test, run the parity, concurrency and design reviews, and open a PR with checklist, screenshots and "How to verify" steps for the reviewer. Use when asked to work on, implement or fix an issue (e.g. "implement #12").
argument-hint: <issue number>
---

# Implement an issue

Follow these steps in order. Talk to the user in German; everything written to the repo or GitHub is English and never names or addresses the product owner (write "the reviewer" or "you"). Never push to `main`, never merge.

## 1. Read the issue
- `gh issue view <N> --comments`
- Note the parity IDs, acceptance criteria, milestone and labels. If acceptance criteria are missing or ambiguous, ask the user before planning.
- Check that no open PR already covers it: `gh pr list --search "<N>"`.
- Check that it is not blocked (open "blocked by" issues or the label `needs-decision`, see "Dependencies and decisions"). If it is, tell the user and do not start.
- Set the issue's status on the project board to **In Progress** (see "Project status" below).

## 2. Study the original
- Read the parity rows for every ID in `docs/feature-parity.md`, including "Native replacement", "Inconsistencies found" and "Known defects – do not replicate".
- Read the old code at the referenced file:line locations and follow it until the full behavior is clear: `../SlidePilot-macOS/SlidePilot/` (local) or `/opt/reference/SlidePilot-macOS/SlidePilot/` (cloud).
- Read the matching docs page: `https://slidepilot.gitbook.io/slidepilot/basic-features/<page>.md`.
- Read the relevant ADRs in `docs/decisions/` and the affected sections of `docs/architecture.md`.

## 3. Plan
- Write down: behaviors to reproduce (with old source), deviations (only those already approved), which module each piece belongs in (Core / Rendering / RemoteProtocol / app), the native components to use (ADR 0010), and the tests.
- **Stop and ask the user** if the plan needs a new deviation from parity, a new dependency, an architectural decision (→ propose an ADR in chat), or custom UI beyond the slide surface, pointer overlay and drawing layer.
- Create the branch with three separate commands (no `&&`, see "Sandbox and permissions" in `CLAUDE.md`): `git checkout main`, `git pull origin main --ff-only`, `git checkout -b feat/<short-name>` (or `fix/…`).

## 4. Tests first
- Write Swift Testing tests (`import Testing`, `@Test`, `#expect`) for the logic in the package where it lives. Cover the old behavior's edge cases and the "do not replicate" defects (as regression tests that assert the correct behavior).
- New test targets must be added to `SlidePilot.xctestplan`.

## 5. Implement
- Follow `CLAUDE.md`: Swift 6 strict concurrency, `@Observable`, `@MainActor` UI state, actors for background work, no `DispatchQueue`, no third-party dependencies.
- UI: native components only (see "Native replacement"). System colors and semantic fonts, SF Symbols, accessibility labels, keyboard shortcuts via `Commands`.
- Strings in `SlidePilot/Resources/Localizable.xcstrings` with en, de and fr.
- No personal data in code, comments, commits or screenshots (see "Privacy" in `CLAUDE.md`). Check `git config user.email` is the noreply address.

## 6. Build and test
- Local session: run every command from "Build and test" in `CLAUDE.md` (macOS with all package tests, iPad simulator), each as a single command without pipes. Zero warnings, all tests green.
- Cloud session (no toolchain): push the branch, open a **draft** PR, and iterate with `gh pr checks <PR> --watch` and `gh run view <run-id> --log-failed` until `ci-success` is green.
- Manually run the app on macOS and in an iPad simulator and walk through every acceptance criterion. Check light and dark mode, Dynamic Type on iPad (Xcode Environment Overrides or `xcrun simctl ui <device> content_size extra-extra-large`), VoiceOver labels (Accessibility Inspector), and keyboard-only use.

## 7. Reviews
Run the review agents on the branch diff and fix what they find. Repeat until each one reports `PASS` or only notes you can explain.
1. `parity-reviewer`: always. Give it the parity IDs.
2. `design-reviewer`: whenever UI changed.
3. `concurrency-reviewer`: whenever actors, async code, tasks, rendering, file observation, networking or shared state changed.

Then update `docs/feature-parity.md` (status `done` for fully matched items, notes for partial ones) and, if needed, `docs/architecture.md`.

## 8. Screenshots
- iPad simulator: copy the fixtures with `scripts/sim-copy-fixtures.sh <UDID>` and open one from the document browser (see "iPad simulator testing" in `CLAUDE.md`), then `xcrun simctl io <device> screenshot ./.pr-screenshots/<file>.png`. Take light and dark (`xcrun simctl ui <device> appearance dark`).
- macOS: **only app-rendered snapshots** (see "Mac snapshots" in `CLAUDE.md`). Add a test per changed view or window to `SlidePilotMacSnapshots/MacSnapshots.swift` (light and dark, fixtures only, loaded with `Fixture.data("<file>.pdf")`), run the `SlidePilotMacSnapshots` scheme and export with `python3 -I scripts/export-mac-snapshots.py` into `./.pr-screenshots/mac/`. Never capture the Mac screen itself (`screencapture`, ScreenCaptureKit, Screenshot.app, UI-test screen captures). Look at every exported PNG before attaching it. Still add a "Visual check (Mac)" section for what snapshots cannot show (menus, popovers, Liquid Glass, real window behavior).
- Save screenshots in the git-ignored `./.pr-screenshots/` folder (never committed) and check that no personal data is visible (file paths, user or device names). Absolute, `~` and `../` paths are denied for screenshots and attachments.
- Upload with `gh pr create --attach ./.pr-screenshots/<file>.png` / `gh pr edit <PR> --attach ./.pr-screenshots/<file>.png`. Reference them in the body as `![iPad dark](./.pr-screenshots/ipad-dark.png)`; gh rewrites the path to the uploaded URL. Use `--attach './.pr-screenshots/<file>.png#Alt text'` for alt text. Uploaded files of a public repo are publicly reachable.
- Pass the PR body inline with `--body '…'` and without backticks (they keep gh in the sandbox, where it fails); `--body-file`, `-F` and `--template` are denied.
- Cloud sessions cannot take screenshots: say so in the PR and make "How to verify" more detailed.

## 9. Open the PR
- Commit with an imperative English subject and a body explaining why. End commit messages and PR descriptions with the attribution lines from the session instructions.
- `gh pr create --attach …` (or mark the draft ready and `gh pr edit --attach …`) with `Closes #<N>`, the issue's milestone, and the body from `.github/pull_request_template.md`:
  - Summary (2-4 sentences) and parity IDs
  - What the reviewer should check (decisions, deviations, justified custom UI)
  - **How to verify**: numbered click-by-click steps on Mac and iPad that need no code reading, with expected results
  - iPad screenshots (light/dark) and the "Visual check (Mac)" section
  - Review results (one line per agent)
  - Known limitations and follow-ups
- Keep it short (see "PR workflow" in `CLAUDE.md`): leave out sections that do not apply, no file-by-file list, one sentence per bullet, background goes into docs or an ADR.
- Set the issue's status to **In Review** once the PR is open and no longer a draft (see "Project status").
- If the work came from a prototype PR, close that PR (`gh pr close <N>`, never merge it, keep its branch) once the findings PR is open.
- Wait for `ci-success` to be green, then tell the user in German (short): what was done and the PR link, ending with the "Was du tun musst" section from `CLAUDE.md` (decisions, checks, settings).

## Project status
Issues live on project number 4 of the SlidePilot organization (`gh project … 4 --owner SlidePilot`). Its Status field has Backlog, In Progress, In Review and Done. GitHub sets Done when the PR is merged; set the other two yourself.
- Field and option IDs: `gh project field-list 4 --owner SlidePilot --format json` (field "Status").
- Item ID of the issue: `gh project item-list 4 --owner SlidePilot --format json --limit 200`, the item whose `content.number` is the issue number (use `--jq` instead of a pipe).
- Set it: `gh project item-edit --id <item> --project-id <project> --field-id <status field> --single-select-option-id <option>`.
- If a new issue is not on the board yet, tell the user instead of adding it.

## Dependencies and decisions
The board is the live project overview, so blockers must be on the issues themselves. There is no extra status for waiting; views filter on these instead ("Ready to start", "Waiting for you", "Blocked", see `docs/project-board.md`).
- **Blocked by another issue:** use GitHub's native issue dependency ("blocked by"), never a label or a sentence in the body. GitHub unblocks the issue when the blocker closes. Set it with the GraphQL mutation `addBlockedBy` (`gh api graphql -f query='mutation { … }'`; get node IDs with `issue(number: N) { id }`). Batch several mutations into one call.
- **Waiting for a product-owner decision** (approval of a deviation or proposal, prototype acceptance): add the label `needs-decision` and say in a comment what has to be decided. Remove the label once the decision is made.
- When you create an issue, set its dependencies right away. When an issue turns out to depend on another one, add the dependency then.
- An issue that was already started and then becomes blocked stays **In Progress**; it shows up under "Blocked" through the dependency. Do not move it back to Backlog.
- Never remove a dependency just to start work; if you think it is wrong, ask the user.
