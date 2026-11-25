# User documentation for 2.0

The user documentation lives on GitBook (<https://slidepilot.gitbook.io/slidepilot>), outside this repository; the app's Help command opens it (SET-06). This page lists what each GitBook page needs for 2.0, so the site can be updated before the release. Behavior details are in [`feature-parity.md`](feature-parity.md) (IDs in brackets); the pricing rules are in [ADR 0020](decisions/0020-free-app-with-pro-purchase.md).

## Whole site
- SlidePilot 2.0 runs on macOS 26, iPadOS 26 and iOS 26 (iPhone) as one App Store app. Pages that say "Mac" or show only Mac menus need an iPad and iPhone note: the same commands are in the toolbar, its overflow menu and the settings sheet; keyboard shortcuts work with a hardware keyboard.
- Replace all Mac screenshots (old AppKit look) with 2.0 screenshots, light mode. The App Store screenshots in the git-ignored `.pr-screenshots/store/` can be reused.
- Remove mentions of the Touch Bar (DROP-01) and of "Check for Updates…" (DROP-02).

## Overview (`master`)
- New: free App Store app with the in-app purchase SlidePilot Pro. Everything on the presenter's own device is unlimited; audience output (external display, AirPlay, the Mac presentation window) and the remote are 3-minute trials without Pro. Restore Purchases is in Settings.
- The free Mac download (website, GitHub Releases) has no limits and no purchase.
- Several documents can be open at once, each in its own windows (DOC-01, DOC-07).

## Changelog and Release Plan
- Add a 2.0 entry: rewrite, iPad and iPhone, remote between any two devices, saved notes and drawings, Pro purchase. Mark the old release plan as done or remove it.

## FAQ and Troubleshooting
- Add: why the presentation stops after 3 minutes (trial without Pro), how to restore a purchase, and that the free Mac download has no limits.
- Add: where notes, drawings and settings are stored now (one companion entry per PDF inside the app, matched even if the PDF moves; NOTES-10) and the "take over data" offer for a moved or renamed PDF (NOTES-12).
- Old RTF notes next to the PDF are imported automatically on the Mac (NOTES-08, NOTES-10).
- Check every entry about permissions and file access: the app is sandboxed now (DOC-10).

## Screens
- Mac: the presentation window goes to the second screen in full screen as before; on iPad and iPhone the audience sees an external display or AirPlay (DOC-05).
- Mac: the title bar of the presentation window is a native hidden title bar (DOC-06).
- The presentation is a Pro feature with a 3-minute trial; the audience screen shows "SlidePilot – Trial Version" during the trial.

## Slide Overview (`customize-layout`)
- No layout editor any more: the slot contents are chosen in the window with View ▸ Arrangement or the toolbar's Layout menu (one picker per slot). Settings ▸ Layout keeps padding and time display size (LAY-04).
- The layout is stored per document; a document without one opens with the last-used layout (LAY-05).
- Slot titles are one compact line, e.g. "Current 3 / 20" (LAY-10). The end of the deck shows "End of presentation" (LAY-09).
- The slide navigator sidebar can be resized; the page field clears after Return (LAY-06).

## Timing
- The clock follows the system's 12/24-hour setting (TIME-01).
- Set Timer (T) is always available; setting a time switches to timer mode, zero goes back to the stopwatch (TIME-03, TIME-04). The timer warnings are in the Time menu. Times no longer drift during long talks (TIME-07).

## Notes
- Notes save automatically; New/Open/Save Notes are replaced by the automatic companion storage and import (NOTES-06, NOTES-07, NOTES-10).
- Notes Mode is in the View menu (NOTES-01); split positions unchanged (NOTES-02).
- The editor uses the system colors in light and dark mode (NOTES-04); font size changes (NOTES-05).

## Drawing
- The drawing tools are in the window toolbar: the same six colors in a color menu, a White Canvas toggle, the eraser and Done (DRAW-03). Apple Pencil double-tap and squeeze follow the system setting (DRAW-11).
- "Save drawings" keeps drawings across reloads and reopening (DRAW-07).
- Export Drawings exports a PDF with the drawings (DRAW-10).

## Curtain
- Clicking or tapping the "Hidden Screen" warning hides the curtain (CUR-02). Check the shortcut list against CUR-01.

## Pointer
- The pointer editor is in Settings ▸ Pointer (PTR-04); the custom pointer is global (PTR-05, PTR-07).

## Remote
- Rewrite the page: there is no separate remote app. Any SlidePilot (iPhone, iPad, Mac) can control any other one on the same network and be controlled (REM-01).
- Pairing: choose the device in Settings ▸ Remote, confirm the code shown on both devices; trusted devices reconnect automatically (REM-02). The connection is encrypted and only paired devices can control (REM-06).
- Remote control is a Pro feature with a 3-minute trial per connection on each App Store installation without Pro.

## Pre-Rendering
- No settings any more: the app renders the current and next slides first and keeps a memory budget of its own (PRE-01, PRE-02). The page can shrink to one paragraph or move into the FAQ. Measurements: [`performance.md`](performance.md).

## Shortcuts
- Update the table from `feature-parity.md` (changed: NAV-02, NAV-03, CUR-01; removed: the "New/Open/Save Notes" shortcuts). Add a note that iPad and iPhone show all shortcuts when you hold ⌘ with a hardware keyboard.

## LaTeX Support
- Add links to local files (`\href{run:…}`, NAV-06) and embedded videos (`\movie`, NAV-07) if they are not described yet.
