# Prototype: auto-reload when the PDF changes on disk

Issue #10 · Parity DOC-08, DEF-06 · ADR 0013 · Phase 1 – Risk Prototypes

## Question

The old app reloads the PDF when a LaTeX recompile changes it (DOC-08). It watches the opened file with a kqueue source for `.write` only and never re-opens it, so watching stops after an atomic save (DEF-06). The new app is sandboxed and runs on iPadOS, where the PDF often comes from iCloud Drive. This prototype measures which change notifications arrive for the ways tools write a PDF, whether access to the opened PDF survives a replaced file, and how to reload without picking up a half-written file.

## What was tried

Prototype code on the branch `proto/auto-reload` (draft PR #66, not merged). It runs four watchers side by side on the same PDF:

| Watcher | How |
|---|---|
| legacy | The old `FileObserver`: kqueue (`DispatchSource`) on the file, `.write` only, never re-opened |
| vnode | kqueue on the file, all events, re-opens the path after delete/rename |
| presenter | `NSFilePresenter` registered with `NSFileCoordinator` (what `NSDocument`/`UIDocument` use) |
| poll | `stat()` every 250 ms (inode, size, modification time) |

Every event feeds a **candidate reload pipeline**: wait until no event arrived for 300 ms, read the whole file with a coordinated, security-scoped read, validate it (`%PDF-` header, `%%EOF` in the last 1 KiB, PDFKit opens it, at least one page), retry every 300 ms up to 10 times, and skip the result if its SHA-256 equals the loaded version. The page index is kept and clamped to the last page.

**Simulated write patterns** (3 → 5 → 2 pages, same pattern twice in a row):

| Pattern | Stands for |
|---|---|
| in-place, chunked | pdflatex/lualatex/xelatex (also via latexmk): truncate the file, write it in chunks |
| in-place, slow | the same with pauses longer than the debounce (large deck) |
| atomic rename | `Data.write(.atomic)`, many sync clients, build into another folder + `mv` |
| replaceItemAt | safe save of document-based apps |
| delete + recreate | build scripts that clean first |
| coordinated replace | Files app, iCloud |
| touch only | modification date changes, bytes stay the same |

They ran as package tests on the Mac (not sandboxed) and in the iPad simulator, and inside the sandboxed Mac app (hosted test). A `DocumentGroup(viewing:)` probe app showed events and reloads for **real recompiles**.

**Environment:** Apple-silicon Mac, macOS 27.0.1, Xcode 27.2, Debug builds. iPad simulator: iPad Pro 13-inch (M5), iOS 27.2. Device: iPhone, iOS 27.0, PDF in iCloud Drive recompiled on the Mac. No iPad was available; the iOS sandbox, document picker, file presenters and iCloud sync behave the same on iPhone and iPad.

## Measurements

### Simulated writes: events per rewrite (rewrite 1 / rewrite 2)

Sandboxed Mac app; the Mac package test and the iPad simulator gave the same picture.

| Pattern | legacy | vnode | presenter | poll | Pipeline |
|---|---|---|---|---|---|
| in-place, chunked | 8 / 8 | 11 / 9 | 1 / 1 | 3 / 3 | OK |
| in-place, slow | 4 / 4 | 6 / 5 | 3 / 3 | 4 / 4 | OK, 2 attempts (half-written file rejected) |
| atomic rename | **0 / 0** | 2 / 2 | 1 / 1 | 1 / 1 | OK |
| replaceItemAt | **0 / 0** | 2 / 1 | 1 / 1 | 1 / 1 | OK |
| delete + recreate | **0 / 0** | 2 / 2 | 1 / 1 | 2 / 2 | OK |
| coordinated replace | **0 / 0** | 4 / 2 | 2 / 3 | 1 / 1 | OK |
| touch only | 0 / 0 | 1 / 2 | 1 / 1 | 1 / 1 | OK, no reload |

"OK" means the pipeline ended on the right page count and never showed a wrong version.

**Timing** (from the start of the write): vnode reports at once (0–10 ms). The presenter reports uncoordinated changes after **about 1.06 s** on every platform; coordinated writes arrive as `deletion` at 3 ms and `didChange` at about 0.53 s. During a long in-place write the presenter fires repeatedly (about every 1.4 s).

### Real recompiles

| Case | Mac, local folder | iPhone, iCloud Drive (recompiled on the Mac) |
|---|---|---|
| pdflatex, in place | legacy + vnode: ~100 write events in 0.3 s; presenter `didChange` 1.07 s after the first event; reloaded after 0.73 s | – |
| Built elsewhere + `mv` (new inode) | legacy: **nothing**; vnode `delete`; presenter `didChange` 1.06 s later; reloaded after 0.40 s | Sync arrives as a replace: vnode `delete`, presenter `didChange` 0.53 s later; reloaded after 0.58 s |
| Shorter deck (6 → 5 pages, from the last page) | reloaded, ended on page 5 of 5 (clamped) | not seen in the report |
| Access to the opened PDF after the change | security-scoped read OK every time | security-scoped read OK |
| `DocumentGroup` re-delivered the document | never | **yes**, once per synced change |

The iPhone report shows one synced change; further recompiles during the test did not show up as separate versions.

### Other findings

- **Spurious events are common.** On the Mac the PDF got attribute-only changes three times before any recompile (system services such as Spotlight or Quick Look), each with a presenter `didChange`. On iOS the presenter reports iCloud metadata (`ubiquityAttributes`) right after opening and around every sync. The digest check turned all of them into "unchanged"; without it each would reload.
- **PDFKit rejects half-written pdflatex files.** Cut at 10 % … 99 % or without the last 8 bytes, `PDFDocument(data:)` returned `nil` for both pdflatex fixtures (`plain-slides.pdf`, `large-deck.pdf` with 320 pages). A Core Graphics PDF without its last 8 bytes still opened with all pages, so the `%%EOF` check is kept as a second guard.
- **An open document is not affected by the rewrite.** A `PDFDocument(url:)` of a 4.5 MiB file kept showing the old version, also for pages first rendered after an in-place rewrite or an atomic rename (Mac sandboxed, Mac, iPad simulator).
- **Bookmarks of a replaced file go stale.** A bookmark of the PDF still resolves to the same path after every pattern. After in-place writes it stays fresh; after atomic rename, `replaceItemAt`, delete + recreate and coordinated replace (new inode) it is reported **stale** and has to be recreated (Mac and iPad simulator).
- **Not tested:** iCloud files that are not downloaded yet, other file providers, network volumes, renaming or moving the PDF while it is open (the presenter API reports moves with `presentedItemDidMove(to:)`), Overleaf's own sync.

## Limits

- **Old watcher (legacy):** dead after the first atomic save, replace or delete + recreate, on every platform. DEF-06 confirmed.
- **kqueue:** fast, but must re-open the path after every replace and never sees iCloud metadata or moves. It needs a `DispatchQueue`, which the project rules exclude.
- **File presenter:** saw every change on every platform, including in-place writes by tools that do not coordinate, with about 1 s delay. It may fire while a long compile is still writing.
- **Sandbox:** a recompile that replaces the file keeps the access to the opened PDF on macOS and iOS; no folder grant is needed for auto-reload.

## Recommendation

Approved by the product owner; recorded in [ADR 0013](../decisions/0013-pdf-change-detection.md).

1. **Watch with a file presenter only.** The file observation actor registers an `NSFilePresenter` for the opened PDF and emits changes through an `AsyncStream`. It follows `presentedItemDidMove(to:)`, and ignores pure iCloud metadata. No kqueue, no polling. Expected reload: about 1.4 s after the compile ends.
2. **Reload through the validated pipeline:** 300 ms debounce, coordinated read of the whole file inside the security scope (asynchronous coordination, so no actor thread blocks), `%PDF-` + `%%EOF` + PDFKit + at least one page, retry every 300 ms up to 10 times, skip unchanged bytes, then create the new `PDFDocument` from the data.
3. **Own the reload in the session, not in `DocumentGroup`.** iOS re-delivers the document after a change, macOS does not; the digest check keeps the iOS delivery from loading twice.
4. **Keep the page, clamp it** to the new last page when the deck got shorter (the old app kept an invalid index, DEF-18). Notes are padded to the new page count as before. Drawings follow DRAW-07.
5. **Refresh stale bookmarks** of the PDF after a reload, so the companion file match (ADR 0012) survives recompiles that replace the file.

## Follow-ups

- #24 (auto-reload): implement items 1–4; test renaming and moving the open PDF, and an iCloud file that is not downloaded.
- #25 (companion file): refresh a stale PDF bookmark when it resolves (item 5).

## Re-running

Check out `proto/auto-reload`.
- Simulated patterns: `-only-testing:SlidePilotRenderingTests/ReloadMeasurements` on My Mac or an iPad simulator; reports are written to `build/reload-reports/`. Inside the sandboxed app: scheme `SlidePilotMacSnapshots`, `-only-testing:SlidePilotMacSnapshots/ReloadSelfTest` (the report is printed to the test log).
- Real recompiles: run the scheme `SlidePilot` on a Mac, iPad or iPhone, open a PDF from a copy of `Fixtures/`, recompile it and use Copy Report (no paths or file names). Steps are in PR #66.
