# Architecture Decision Records

| ADR | Title | Status |
|---|---|---|
| [0001](0001-minimum-os.md) | Minimum OS: macOS 26 and iPadOS 26 | Accepted |
| [0002](0002-public-repo-english-gpl.md) | Public repository, English only, GPLv3 | Accepted |
| [0003](0003-app-store-distribution.md) | App Store distribution | Superseded by 0011 |
| [0004](0004-architecture.md) | One project, multiplatform target, local packages | Accepted |
| [0005](0005-pre-rendering.md) | Leaner pre-rendering cache | Accepted (scope after Phase 1) |
| [0006](0006-remote-protocol.md) | New remote protocol, shipping in 1.1 | Accepted |
| [0007](0007-notes-companion-file.md) | Companion file for notes, drawings and settings | Accepted (iPad access in Phase 1) |
| [0008](0008-ci-as-build-feedback.md) | GitHub Actions as build feedback | Accepted |
| [0009](0009-drop-touch-bar.md) | Drop Touch Bar support | Accepted |
| [0010](0010-native-design-first.md) | Native design first | Accepted |
| [0011](0011-universal-purchase-and-direct-download.md) | Universal purchase and free Mac download | Accepted |

## Process
1. Propose the decision in chat with the product owner (context, options, recommendation).
2. Only after approval, write the ADR with the next free number using the template below, and update this index in the same PR.
3. Accepted ADRs are not edited. To change a decision, write a new ADR and mark the old one `Superseded by NNNN`.

## Template
```markdown
# NNNN – Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
## Decision
## Consequences
```
