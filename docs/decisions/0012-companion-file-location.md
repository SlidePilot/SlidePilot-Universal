# 0012 – Companion file in the app container, folder access on demand

- Status: Accepted
- Date: 2026-11-12

## Context
ADR 0007 introduced one companion file per PDF (notes, drawings, per-document settings) and left its location open until sandbox and iPad file access were verified. The Phase 1 prototype (issue #9, [findings](../prototypes/file-access.md)) showed on macOS (local folder) and iOS (iCloud Drive):

- Without a folder grant a sandboxed app reaches only the opened PDF and its own container. It cannot write next to the PDF, read legacy notes or read videos. Related items (`NSIsRelatedItemType`) did not help.
- On macOS the app can see that a file next to the PDF exists; on iOS it cannot.
- One folder grant gives full access to the folder. Stored as a bookmark it works for other PDFs in the folder and after relaunches.

## Decision
- The companion file lives in the **app container**. It is matched to its PDF through a security-scoped bookmark (and the `documentIdentifier` where the system provides one), so renames and moves keep the match.
- Container entries that contain notes or drawings **do not expire**. The 28-day expiry (old per-document settings) applies only to entries that hold nothing but settings.
- Access to the PDF's folder is requested **only when needed** and stored as a bookmark:
  - when the PDF references neighbouring files (`\movie`, `run:` links; NAV-06/07), on all platforms;
  - on macOS, when a legacy notes file exists next to the PDF (NOTES-08).
- On iPadOS legacy notes are not detected automatically. An **Import Notes…** command imports an RTF file (parity deviation of NOTES-08, approved by the product owner).
- Whether a stored folder grant covers a PDF is decided by file system relationship, not by comparing path strings.

## Consequences
- Notes and drawings are saved without any prompt, on every platform and location.
- Notes do not travel with the PDF to another device or into a copied project folder. RTF export (NOTES-06/10) stays the way to move them. Sync is out of scope for 1.0.
- Users who present videos or keep legacy notes grant folder access once per folder.
- NOTES-08 is `changed` (iPad import instead of auto-load). DOC-10, NOTES-10 and SET-02 notes reference this ADR.
