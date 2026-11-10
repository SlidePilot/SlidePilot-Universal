# 0007 – Companion file for notes, drawings and per-document settings

- Status: Accepted (iPad file access verified in Phase 1)
- Date: 2026-11-10

## Context
The old app stored notes in `<pdf>-notes.rtf` next to the PDF (pages separated by `#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-X`), per-document settings in a UserDefaults suite keyed by URL with 4-week expiry, and drawings only in memory.

## Decision
- One companion file per PDF holds notes, drawings and per-document settings in a versioned format defined in SlidePilotCore.
- Legacy notes files are imported automatically on open. Names searched: `<pdf><sep><name>.rtf`, `<sep>` ∈ {`-`, `_`, space}, `<name>` ∈ {`notes`, `Notes`, `Notizen`}.
- RTF export in the legacy format stays possible.
- Where the companion file lives (next to the PDF or in the app container) is decided in Phase 1, after verifying sandbox and iPad file access.

## Consequences
- Drawings can survive PDF recompiles (parity DRAW-07, `changed`).
- Phase 1 prototype: security-scoped access to the PDF's folder on macOS and iPadOS (Files, iCloud Drive, external providers).
