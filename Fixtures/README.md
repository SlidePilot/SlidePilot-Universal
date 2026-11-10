# Test fixtures

Sample LaTeX Beamer documents for prototypes, tests and manual checks. The `.tex` sources and the compiled PDFs are both committed, because CI has no LaTeX. All content is generated and free of personal data.

## Files

| File | Pages | What it covers | Parity IDs |
|---|---|---|---|
| `plain-slides.pdf` | 6 | Plain slides: title, bullets, formula, table, TikZ figure | – |
| `plain-slides-notes.rtf` | – | Legacy notes file for `plain-slides.pdf`, see below | NOTES-08, NOTES-09 |
| `links_Notizen.rtf` | – | Legacy notes file for `links.pdf` with edge cases, see below | NOTES-08, NOTES-09 |
| `notes-right.pdf`, `notes-left.pdf`, `notes-top.pdf`, `notes-bottom.pdf` | 4 | `show notes on second screen=<position>`, **no** keyword. Slide 2 has an internal link (see [Links in split-notes decks](#links-in-split-notes-decks)); slide 3 has no notes | NOTES-01, NOTES-02 |
| `notes-right-rotated.pdf` | 6 | Notes on the right, pages 2–5 with `/Rotate` 0, 90, 180, 270. The arrow points to the top edge of the unrotated slide | NOTES-02 |
| `keyword-sp-right.pdf`, `keyword-sp-left.pdf`, `keyword-sp-top.pdf`, `keyword-sp-bottom.pdf` | 4 | Same decks with the PDF keyword `SP-Right` / `SP-Left` / `SP-Top` / `SP-Bottom`. Should open in Split mode with that position | NOTES-03 |
| `keyword-lowercase.pdf` | 4 | Notes on the right, keyword `sp-right`. Keywords are case-sensitive, so this must **not** be detected | NOTES-03 |
| `keyword-mixed.pdf` | 4 | Notes on the left, Keywords entry `Beamer, SP-Left` (one string in the PDF). Whether the old app detects `SP-Left` depends on how PDFKit splits the string into an array (comma, with or without trimming spaces). **Not yet checked on a Mac**; record the result here and in NOTES-03 | NOTES-03 |
| `links.pdf` | 5 | Internal links (`\hyperlink`, Beamer navigation symbols), `https` and `mailto` URL links | NAV-05 |
| `media.pdf` | 4 | Page 2: `\movie` (multimedia package) with `media/test-pattern.mp4`. Page 3: `\href{run:…}` to the video and to `plain-slides.pdf` | NAV-06, NAV-07 |
| `rotated.pdf` | 6 | Pages with `/Rotate` 0, 90, 180, 270 (pages 2–5), no notes. The arrow points to the top edge of the unrotated page | – |
| `large-deck.pdf` | 320 | Simple pages with a large page number, for render cache measurements | – |
| `media/test-pattern.mp4` | – | 4 s, 320×180, 15 fps, H.264 + quiet 440 Hz AAC tone. Generated with ffmpeg (`testsrc2`), so there are no licensing questions | NAV-06, NAV-07 |

Paths in `media.pdf` are relative to the PDF, so keep the folder layout when copying the fixtures (for example to an iPad).

### What the PDFs contain

- `\movie` creates a `/Movie` annotation whose `/Movie` dictionary has `/F (media/test-pattern.mp4)`.
- `\href{run:…}` creates link annotations with a `/Launch` action and a relative `/F` path.
- URL links are `/URI` actions, internal links are `/GoTo` actions.
- Split-notes decks: each PDF page holds the slide and its notes side by side (left/right: 725.7 × 272.1 pt) or stacked (top/bottom: 362.8 × 544.3 pt). The normal page size is 362.8 × 272.1 pt (4:3).

### Links in split-notes decks

pgfpages places the slide and the notes on one combined page, but pdfTeX does not move the link rectangles with them. Every link keeps the position it has on the plain slide, measured from the bottom-left corner of the combined page. This is how real Beamer output looks, so the fixtures keep it:

- Notes **right** or **top**: the slide is in the bottom-left half, so its links line up with the slide.
- Notes **left** or **bottom**: the links lie in the notes half, not on the slide. The old app does not correct this (it hit-tests with `PDFPage.annotation(at:)`).
- In every split deck, the slide thumbnail in the notes template adds a second copy of the slide's links at the thumbnail's untransformed position.

Use `notes-right.pdf` or `notes-top.pdf` to test link clicks in Split mode (NAV-05).

### Legacy notes files

`plain-slides-notes.rtf` uses the format the old app wrote (`NotesDocument.swift`): every page starts with a line `#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-N`, followed by the page's notes and a newline. Its name matches the auto-load rule `<pdf base name>-notes.rtf`. It covers multi-line notes with an empty line (page 2), bold and italic (page 3), non-ASCII characters (page 4) and an empty page (page 5). `links_Notizen.rtf` covers the other auto-load name variant (`_` and `Notizen`) and the loader's edge cases: text before the first separator (dropped), a wrong page number (`Page-7`, ignored), a separator without a number, and fewer notes pages (3) than PDF pages (5).

Both files are written by hand in the RTF dialect that macOS produces, so they can be edited with TextEdit.

## Rebuilding

Requirements: TeX Live with pdfLaTeX, Beamer, PGF/TikZ and `latexmk`; `ffmpeg` only for the video. On Debian/Ubuntu:

```sh
apt-get install texlive-latex-extra texlive-pictures texlive-fonts-recommended latexmk ffmpeg poppler-utils
```

On macOS, MacTeX (or BasicTeX plus the `beamer`, `pgf` and `latexmk` packages) and `brew install ffmpeg` work as well.

```sh
./Fixtures/build.sh           # rebuild all PDFs
./Fixtures/build.sh --video   # also regenerate media/test-pattern.mp4
```

The script builds every `.tex` file in this folder (files in `common/` are only included) and removes the auxiliary files afterwards. Commit the `.tex` source and the PDF together.

### Reproducibility and metadata

- `build.sh` sets `SOURCE_DATE_EPOCH=1767225600` (2026-01-01 00:00 UTC) and `FORCE_SOURCE_DATE=1`, so the dates and the PDF `/ID` are fixed. With the same TeX Live version, a rebuild produces byte-identical PDFs, independent of the folder the repository is in.
- `common/preamble.tex` sets empty Author, Creator and Producer and suppresses the `PTEX.*` entries (they can contain local file paths).
- The video is encoded without metadata (`-map_metadata -1`, bit-exact flags).

Check the metadata after a rebuild:

```sh
pdfinfo Fixtures/<file>.pdf
```

Author, Creator and Producer must be empty and the dates must be 2026-01-01 00:00:00 UTC.

## Adding a fixture

1. Add `<name>.tex` here; load `common/preamble.tex` right after `\documentclass{beamer}`.
2. Keep it small: plain text, no images or fonts beyond the defaults.
3. Run `./Fixtures/build.sh`, check the metadata with `pdfinfo`, and list the file in the table above.
