# 0013 – Detect PDF changes with a file presenter

- Status: Accepted
- Date: 2026-11-13

## Context
DOC-08 reloads the PDF when a LaTeX recompile changes it. The old app watched the file with a kqueue source for `.write` only and stopped watching after an atomic save (DEF-06). The Phase 1 prototype (issue #10, [findings](../prototypes/auto-reload.md)) compared four watchers for in-place writes (pdflatex), atomic saves, delete + recreate, coordinated writes and iCloud sync, on macOS (sandboxed), the iPad simulator and an iPhone:

- An `NSFilePresenter` saw every change on every platform, including uncoordinated in-place writes, about 1 s after the write; it also reports moves and iCloud metadata.
- A kqueue watcher reports at once, but must re-open the file after every replace and needs a `DispatchQueue`, which the project rules exclude.
- Change notifications also arrive without content changes (system services, iCloud metadata), and during long writes a half-written file is on disk.
- Access to the opened PDF survives a replaced file on macOS and iOS. Bookmarks of a replaced file resolve to the same path but are stale.

## Decision
- The file observation actor uses an **`NSFilePresenter`** for the opened PDF and emits changes through an `AsyncStream`. No kqueue watcher and no polling.
- A change is reloaded through one pipeline: **300 ms debounce**, coordinated read of the whole file inside the security scope, validation (`%PDF-` header, `%%EOF` at the end, PDFKit opens it, at least one page), retries every 300 ms up to 10 times, and **no reload if the bytes did not change**. The new `PDFDocument` is created from the read data.
- The presentation session owns the reload on both platforms; it does not rely on `DocumentGroup` re-delivering the document (iOS does, macOS does not).
- The current page is kept and **clamped to the last page** when the deck got shorter (DEF-18, approved by the product owner).
- A stale PDF bookmark is refreshed after a reload.

## Consequences
- A reload appears about 1.4 s after the compile ends instead of almost at once. Accepted for a recompile workflow.
- No exception to the no-`DispatchQueue` rule is needed; the presenter runs on its own `OperationQueue`.
- Renames, moves and iCloud sync are handled by the same mechanism on macOS and iPadOS.
- DOC-08 references this ADR. DEF-18 records the old index behavior.
