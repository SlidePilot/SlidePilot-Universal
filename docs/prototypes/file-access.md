# Prototype: sandbox file access and companion file location

Issue #9 · Parity DOC-10, NOTES-08 (also NAV-06, NAV-07, NOTES-10, SET-02) · ADR 0007, ADR 0012 · Phase 1 – Risk Prototypes

## Question

The new app is sandboxed on macOS and iPadOS (DOC-10). The old app was not, and it read and wrote files next to the PDF: legacy notes `<pdf><sep><name>.rtf` (NOTES-08), videos and `run:` targets referenced by relative paths (NAV-06/07). ADR 0007 left open where the companion file (notes, drawings, per-document settings) lives: next to the PDF, or in the app container keyed by a bookmark. This prototype measures what a sandboxed app can reach next to an opened PDF, with and without a folder grant, and whether grants survive relaunches.

## What was tried

A probe app on the branch `proto/file-access` (draft PR #55, not merged). It opens PDFs through `DocumentGroup(viewing:)`, the planned Phase 2 approach, and runs these probes on the opened PDF:

- read the PDF, without and with `startAccessingSecurityScopedResource()`
- list the PDF's folder
- find and read the legacy notes under all 9 auto-load names
- read `media/test-pattern.mp4` and `plain-slides.pdf` next to the PDF (fixture layout of `media.pdf`)
- write `<pdf>.slidepilot` next to the PDF: directly, and on macOS as a related item (`NSFilePresenter` with `primaryPresentedItemURL`, the companion type declared with `NSIsRelatedItemType`), atomic and non-atomic
- write a companion file into the app container (Application Support)
- create bookmarks of the PDF and the folder, store them, resolve them after a relaunch

A toolbar action grants access to a folder (`fileImporter` for a folder). The folder bookmark is stored and used automatically for later PDFs in that folder. Build settings on the prototype branch: user-selected files read-write, PDF document type, companion type exported with the extension `slidepilot`.

**Test data:** a copy of `Fixtures/` (keeps `media/` and `plain-slides-notes.rtf`).

**Environment:**
- Mac: macOS 27.0.1, local folder on the internal volume (the main use case), Debug build from Xcode.
- iOS: iPhone, iOS 27.0, folder in iCloud Drive, cable build from Xcode. No iPad was available; the iOS sandbox and the document picker behave the same on iPhone and iPad, so the results stand for iPadOS. Not tested: On My iPad, USB drives, third-party file providers.
- The iPad simulator could not be used: it had no network to load the fixtures, and it cannot represent iCloud Drive.

## Measurements

| Probe | Mac, no grant | Mac, folder grant | iOS iCloud, no grant | iOS iCloud, folder grant |
|---|---|---|---|---|
| Read the PDF | OK | OK | OK | OK |
| List the folder | denied | OK | denied | OK |
| Legacy notes: `fileExists` | **true** | true | **false** | true |
| Legacy notes: read | denied | OK | denied | OK |
| `media/test-pattern.mp4`: `fileExists` | **true** | true | **false** | true |
| `media/test-pattern.mp4`: read | denied | OK | denied | OK |
| Write `<pdf>.slidepilot` next to the PDF | denied | OK | denied | OK |
| Same as related item (macOS only) | denied (atomic and non-atomic) | OK | – | – |
| Write a companion file in the app container | OK | OK | OK | OK |
| Folder grant reused for another PDF in the folder | – | OK, no prompt | – | OK, no prompt |
| Bookmarks resolved after relaunch | OK, not stale | OK, not stale | OK, not stale | OK, not stale |
| `documentIdentifier` of the PDF | missing | missing | present | present |

"Denied" is `NSCocoaErrorDomain` 513 or 257 with POSIX error 1 (operation not permitted).

Further observations:

- **Related items do not help.** Writing `<pdf>.slidepilot` as a related item failed, also with the extension declared in `CFBundleTypeExtensions` and with a non-atomic write. The legacy notes would not qualify anyway, because their base name differs from the PDF's.
- **Case sensitivity:** the Mac volume is case-insensitive, so `-Notes.rtf` and `-notes.rtf` matched the same file. On iOS only the exact name `-notes.rtf` matched. The search order of the old app (`Notes`, `notes`, `Notizen` per separator) must therefore be kept on case-sensitive volumes.
- **A stored folder grant was not always matched** to a newly opened PDF on iOS. The prototype compared path strings (folder path as prefix of the PDF path). After a relaunch the same iCloud folder did not match, so iOS seems to report the path in a different form. Production code must not compare path strings; use `FileManager.getRelationship(_:of:in:toItemAt:)` or compare resolved file resource identifiers.
- **The sandbox extension for an opened document lasts for the process.** On the Mac a PDF opened earlier in the same run stayed readable when another PDF was probed. This is not a reliable way to reach other files.
- **Not tested:** iCloud files that are not downloaded yet (placeholders). With a folder grant the app may still not see them until they are downloaded; the loader should coordinate reads (`NSFileCoordinator`) and trigger the download.

## Limits

- **macOS:** without a folder grant the app reaches only the PDF and its own container. It can see (but not read) files next to the PDF.
- **iOS / iPadOS:** without a folder grant the app reaches only the PDF and its own container, and it cannot even see files next to the PDF.
- **Both:** one folder grant gives full read and write access to the folder and its subfolders. Stored as a bookmark it lasts across PDFs and relaunches.

## Recommendation

Approved by the product owner; recorded in [ADR 0012](../decisions/0012-companion-file-location.md).

1. **The companion file lives in the app container**, not next to the PDF. It is matched to the PDF through a bookmark (plus `documentIdentifier` where available), so it survives renames and moves. This works on every platform and location without a prompt. Writing next to the PDF would need a folder grant for every new folder just to save notes.
2. **The folder grant is requested only when it is needed**, with a short explanation, and stored as a bookmark:
   - Videos and `run:` links (NAV-06/07): the PDF itself says whether it references neighbouring files, so the app asks on all platforms when such a reference is first used (or when the document opens).
   - Legacy notes on macOS (NOTES-08): the app sees that a legacy notes file exists and then asks for the folder, so auto-load keeps working after a one-time grant.
   - Legacy notes on iPadOS: the app cannot see the file. Instead of auto-detection there is an **Import Notes…** command (`fileImporter` for RTF). Parity deviation, approved.
3. **No expiry for notes and drawings.** The 28-day expiry of the old per-document settings applies only to container entries that hold nothing but settings. Entries with notes or drawings are kept until the user removes them.
4. **Open-panel defaults:** the folder picker starts in the PDF's folder (`fileDialogDefaultDirectory`), so the grant is one click on the Mac.

## Follow-ups

- #12 (open PDF documents): `DocumentGroup(viewing:)` delivers a readable URL on both platforms; no extra scope handling needed for the PDF itself.
- #25 (companion file and per-document settings): container location, bookmark matching, no expiry for notes and drawings.
- #26 (legacy RTF notes): macOS asks for the folder when a legacy file exists; iPadOS gets Import Notes…; keep the case-sensitive search order.
- #20 (videos and `run:` links): ask for the folder when the PDF references neighbouring files.
- #10 (auto-reload prototype): watching the PDF needs no folder grant; recompiles that replace the file (new inode) should be checked there.
- Mac↔iPad sync of notes is not covered by the container location. It is out of scope for 1.0; RTF export remains the way to move notes.

## Re-running

Check out `proto/file-access`, run the scheme `SlidePilot` on My Mac or on an iPhone/iPad, open a PDF from a copy of `Fixtures/` and use the toolbar (Grant Folder Access, Check Stored Bookmarks, Copy Report). The report contains no paths or file names.
