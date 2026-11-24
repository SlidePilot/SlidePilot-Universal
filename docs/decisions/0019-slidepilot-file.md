# 0019 – The `.slidepilot` file: export and import of a PDF's stored data

- Status: Accepted
- Date: 2026-11-23

## Context
Notes, drawings and per-document settings live in the app container (ADR 0012). Users cannot see that data, keep a copy or move it to another device; RTF export (NOTES-06) only carries the notes. NOTES-11 adds a file that carries everything SlidePilot stores for one PDF. A new file type is architectural: it is registered with the system and has to stay readable across app versions and platforms.

## Decision
- **One flat UTF-8 JSON file** with the extension `slidepilot`, encoded by `SlidePilotFileFormat` (SlidePilotCore):
  `{"slidePilotFileVersion": 1, "exportedAt": "…", "pdf": {"fileName": "…", "pageCount": N}, "settings": {…}, "notes": {…}, "drawings": {…}}`.
  Settings, notes (one RTF document per page) and drawings (relative strokes) use the same encodings as the companion file, so Mac and iPad read the same data.
- **Not in the file:** the PDF's bookmark and document identifier (they contain local paths with the user name), the entry ID, the last-opened date, declined orphans (NOTES-12) and the declined legacy notes flag (NOTES-08). These are state of one device. The PDF itself is never embedded.
- **Version:** its own number, independent of the companion format. Readers ignore unknown keys, so new optional fields keep the version. A file with a higher version than the app knows is refused with a message, so an older app never drops data it does not understand. A package (folder) was rejected: it breaks in mail and on some file shares, and there is nothing binary to keep apart.
- **Type:** an exported `UTType` whose identifier is the bundle ID plus `.slidepilot` (`$(PRODUCT_BUNDLE_IDENTIFIER).slidepilot` in `Info.plist`, derived from `Bundle.main` in code), conforming to `public.data` and `public.content`. It does not conform to `public.json`, so the system does not offer text editors for it. It is a document type of the app (role Viewer, rank Owner).
- **Import replaces:** notes and drawings of the target PDF are replaced as a whole; per-document settings in the file override the stored ones, settings the file does not contain stay. If the PDF already has stored data, or its file name or page count differs from the file, the app asks first. Notes and drawings of pages beyond the PDF's page count are kept, as after an auto-reload (NOTES-10). With "Save drawings" off (DRAW-06) the file's drawings are not imported.
- **Where:** File ▸ Import SlidePilot File… and Export SlidePilot File… (no shortcuts: ⇧⌘O/⇧⌘E and ⌥⌘E are taken), the iPad toolbar's Import and Export menu (export as a share sheet), and Export… per entry in the stored data overview (SET-07). Opening a `.slidepilot` file (double-click, AirDrop, Open With, File ▸ Open, Files on iPad) opens it as a document of its own that shows what it holds and applies it to an open PDF or to a PDF the user chooses.

## Consequences
- Users can keep a visible copy of their notes and drawings and move them between Mac and iPad or to another user.
- The exported file contains no local paths or device identifiers, so it can be shared.
- The type identifier changes with the bundle ID (e.g. the test build's suffix); the extension stays the same, so files open in every build.
- Changing the meaning of a field or the encoding of notes or drawings needs a new file version and a migration in `SlidePilotFileFormat.decode`.
