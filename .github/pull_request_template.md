<!--
Keep it short. Leave out any section that does not apply instead of writing "None" or "not run".
No file-by-file list of changes (the diff shows that). One sentence per bullet.
Background that is worth keeping goes into docs/ or an ADR; link it here.
Docs, config and CI PRs: Summary, What to check and, if useful, How to verify are enough.
-->
## Summary
<!-- What changed and why, in 2-4 sentences. Closes #N -->

**Parity IDs:** 

## What to check
<!-- Decisions, deviations from the old app, justified custom UI, open questions. -->

## How to verify
<!-- Numbered click-by-click steps on Mac and iPad with expected results. No code reading required. -->
1. 

## Screenshots
<!-- UI changes only: iPad simulator and Mac snapshots, light and dark. No personal data visible. -->

### Visual check (Mac)
<!-- What the Mac snapshots cannot show (menus, popovers, Liquid Glass, window behavior) and the expected result. -->

## Reviews
<!-- One line per agent that ran: parity-reviewer, design-reviewer, concurrency-reviewer. -->

## Checklist
<!-- Feature PRs only. The license line applies to every PR. -->
- [ ] Acceptance criteria of the issue are met
- [ ] Tests added/updated (Swift Testing); CI green, no warnings
- [ ] Native components only (ADR 0010); custom UI is justified above
- [ ] Light and dark mode, Dynamic Type (iPad), VoiceOver labels, keyboard navigation checked
- [ ] Strings localized (en, de, fr)
- [ ] `docs/feature-parity.md` (and if needed `docs/architecture.md`) updated
- [ ] No personal data in code, commits or screenshots
- [ ] I agree to the license terms in [CONTRIBUTING.md](https://github.com/SlidePilot/SlidePilot-Universal/blob/main/CONTRIBUTING.md#license-of-contributions) (GPLv3 + license grant for App Store distribution)

## Known limitations
