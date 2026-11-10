# Feature parity inventory

This file is the binding scope for the rewrite. Every feature of SlidePilot for macOS 1.8.0 (build 1.8.0.1) is listed here. A feature may only deviate from the old behavior if the deviation is recorded here (status `changed` or `dropped`) and backed by an ADR or an explicit product-owner decision.

**Sources**
- Old code: `SlidePilot-macOS` at commit `8d38bc1`. Paths are relative to `SlidePilot-macOS/SlidePilot/`. Line numbers refer to that commit.
- Old docs: <https://slidepilot.gitbook.io/slidepilot>. The *Docs* column names the page below `basic-features/` (e.g. `notes` = `basic-features/notes.md`).

**When old code and docs disagree, the code is the reference for behavior.** Disagreements are listed in [Inconsistencies found](#inconsistencies-found).

**Columns**
- **ID:** a stable identifier. Issues and PRs reference it.
- **Native replacement:** the system component that replaces an old UI element (ADR 0010). Parity means the same functionality, not the same look. Custom drawing is allowed only for the slide surface, the pointer overlay and the drawing layer; any other custom UI must be justified in its PR. `–` = no UI element.
- **Milestone:** P1 = Phase 1 – Risk Prototypes, P2 = Presenting, P3 = Notes, Pointer, Drawing, P4 = Remote Protocol, Settings, Localization, P5 = Polish & Release. Remote is implemented in P4 but ships with 1.1, not 1.0 (ADR 0006).
- **Status:**
  - `planned`: not yet implemented.
  - `changed`: implemented, but deliberately different from the old app.
  - `dropped`: will not be implemented.
  - `done`: implemented and parity-reviewed.

---

## 1. Documents and windows

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| DOC-01 | Open a PDF via the open panel. At launch the panel is shown if no document is open, and cancelling leaves the app running without windows | `AppDelegate.swift:187-194,269-294` | – | Document picker / document browser | `DocumentGroup(viewing:)`: system open panel (macOS), document browser (iPad) | P2 | planned |
| DOC-02 | Open from Finder, Dock and Open Recent (`application(_:openFile:)`). Recent documents list with a Clear Menu item | `AppDelegate.swift:314,384`; `Base.lproj/Main.storyboard:64-78` | – | Files app, "Open in", recent list in the document browser | Standard File ▸ Open Recent from `DocumentGroup`; document browser recents (iPad) | P2 | planned |
| DOC-03 | PDF document type declared, role Viewer. The old app used the deprecated extension form; the new app uses the `com.adobe.pdf` UTI | `Info.plist:7-21` | – | Same UTI | – | P2 | changed |
| DOC-04 | Two windows: the **presenter window** (clock, timer, slides, notes) on the main screen and the **presentation window** (current slide, pointer, curtain) | `AppDelegate.swift:197-262` | `screens` | One scene on the device plus an external-display scene. Needs a P1 prototype | SwiftUI scenes: document window for the presenter, separate scene/window for the presentation | P2 | planned |
| DOC-05 | Screen assignment: the presentation window goes to `NSScreen.screens[1]` if there are 2 or more screens, and always enters full screen, even on a single screen. The presenter window becomes key. There is no UI to swap screens; users move windows with Mission Control | `AppDelegate.swift:236-250` | `screens` | External display via `UIWindowScene` role; mirroring must be avoided | System full screen and window placement APIs | P2 | planned |
| DOC-06 | Presentation window: the title bar fades out when the mouse leaves (not in full screen). The window cannot become key while it opens | `PresentationWindowController.swift:14-30`; `PresentationWindow.swift` | – | n/a | Standard window; hidden title bar style for the presentation window | P2 | planned |
| DOC-07 | Closing a window clears its references. Opening a document recreates both windows | `AppDelegate.swift:994` | – | – | – | P2 | planned |
| DOC-08 | Auto-reload when the PDF changes on disk (LaTeX recompile). The reload runs in the background and keeps the current page; notes are padded to the new page count | `Helpers/FileObserver.swift`; `Controllers/DocumentController.swift:39-44,202-226` | – | File presenter on a security-scoped URL. Must also handle atomic saves (see DEF-07) | – | P2 | planned |
| DOC-09 | Window title shows "Presenter Display Edited" when notes have unsaved changes | `PresenterWindowController.swift:28-35` | – | Document-edited indicator | System document-edited indicator from `DocumentGroup` | P3 | planned |
| DOC-10 | App Sandbox with security-scoped bookmarks for the PDF, notes file, recent documents and per-document settings. The old app was not sandboxed | `SlidePilot.entitlements` (empty) | – | Same | – | P1 | changed |
| DOC-11 | Drag and drop of a PDF onto the windows. **Not in the old app**; listed so it is not added by accident | – | – | – | – | – | dropped |

## 2. Layout, slides and navigator

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| LAY-01 | Presenter layout with three slide types (current, next, notes) and four arrangements: single, double, tripleLeft, tripleRight. Default: double with `[current, next, notes]` | `Views/LayoutEditor/LayoutConfiguration.swift:19-157`; `Controllers/DisplayController.swift:75-82` | `customize-layout` | Same; needs a compact arrangement for portrait | macOS: `HSplitView`/`VSplitView`. iPad: no resizable system split exists, custom divider only if justified (decide in Phase 2) | P2 | planned |
| LAY-02 | Toggle the current slide (**A**), next slide preview (**P**) and notes (**N**). The previous triple arrangement and slot positions are remembered when a slide is hidden and shown again | `LayoutConfiguration.swift:57-157`; `AppDelegate.swift:578,636,640` | `customize-layout` | Toolbar buttons + hardware keyboard | Toolbar toggles with SF Symbols + `Commands` menu items | P2 | planned |
| LAY-03 | Drag the separator between slots to resize them. Containers are at least 300 pt wide; in triple layouts the stacked column is split 50/50 | `Views/Slide/SplitView.swift`; `Views/Slide/SlideArrangementView+ViewSetup.swift` | `customize-layout` | Touch drag | Same as LAY-01 | P2 | planned |
| LAY-04 | Layout editor (**⌃⌥L**, opens the Layout settings pane). Arrangement buttons, drag-and-drop slide symbols into slots, padding (0/15/30, default 30) and time display size | `Views/LayoutEditor/*`; `AppDelegate.swift:627` | `customize-layout` | Sheet; drag and drop with touch | Custom drag-and-drop editor → `Form` in the Settings scene (macOS) / sheet (iPad) with `Picker`s for arrangement, slot contents, padding and time size (proposal, confirm in Phase 2) | P2 | planned |
| LAY-05 | Layout is stored **globally** (not per document) in UserDefaults `layoutConfiguration` | `DisplayController.swift:286-296` | – | Same | – | P2 | planned |
| LAY-06 | Slide navigator (**O**, close with the menu or **Esc**). It is a 180-pt thumbnail sidebar with a page-number field. Typing a letter or digit focuses the field and **Return** jumps to the page. Thumbnails do not follow links. Text search was a TODO in the old app and is not part of parity | `Views/Thumbnail/ThumbnailNavigation.swift:318-384`; `PresenterViewController.swift:353-413`; `Views/Thumbnail/ThumbnailView.swift:33` | `customize-layout` | Sidebar / sheet | Custom thumbnail sidebar → `NavigationSplitView` sidebar or `.inspector` with a thumbnail `List`; page field → `.searchable` / toolbar `TextField` | P2 | planned |
| LAY-07 | Optional crossfade between slides on the presentation window (0.6 s). UserDefaults `crossfadeSlides`, default off | `Views/Slide/PDFPageView.swift:280-293`; `Controllers/PreferencesController.swift:120-128` | – | Same | `Toggle` in Settings | P2 | planned |
| LAY-08 | Drawing mode replaces the presenter layout with the current slide only (see DRAW-05) | `SlideArrangementView+ViewSetup.swift:14-37` | `drawing` | Same | – | P3 | planned |
| LAY-09 | End of deck: the next-slide preview shows a black image after the last slide | `Views/Slide/NSColor+Extension.swift` | – | Same | – | P2 | planned |

## 3. Navigation, links and media

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| NAV-01 | Next slide: **→ ↓ PageDown**. Previous slide: **← ↑ PageUp**. Works in both windows (presentation clickers send these keys). **Space and Return are not handled** | `NavigationWindow.swift:13-24` | `shortcuts` | Hardware keyboard + swipe/tap; tap zones are a new design decision | `Commands` + `.onKeyPress`; iPad: swipe gestures and hardware keyboard | P2 | planned |
| NAV-02 | Hidden menu items for previous/next slide: **⌃⌘← / ⌃⌘→** (also work while editing notes) | `Main.storyboard:432-453` | `notes` (as "change slides while editing") | Hardware keyboard | `Commands` items | P2 | planned |
| NAV-03 | Go back to the previously viewed slide (**⌃G**) | `Controllers/PageController.swift`; `Main.storyboard:462` | `shortcuts` | Same | `Commands` item + toolbar back button | P2 | planned |
| NAV-04 | Page switching is blocked while `isPageSwitchingEnabled` is false (drawing mode without "save drawings") | `PageController.swift`; `DisplayController.swift:345-367` | `drawing` | Same | – | P3 | planned |
| NAV-05 | Internal links (`PDFActionGoTo`) jump to the target page. URL links (`PDFActionURL`) open in the default app. A pointing-hand cursor appears only over link annotations | `PDFPageView.swift:334,363-413` | – | Tap; `UIApplication.open` | `.pointerStyle(.link)` over links; `openURL` | P2 | planned |
| NAV-06 | `\href{run:…}`: open a linked local file (e.g. a video in QuickTime, or another document). These are PDF annotations created by LaTeX. How PDFKit exposes them (Launch vs. URL action with a file URL) is checked with the sample PDF fixtures | `PDFPageView.swift:363-413` | `latex-support` | Best effort: Quick Look / share sheet. Sandbox needs access to the PDF's folder | `openURL` / `NSWorkspace`; iPad: `.quickLookPreview` | P2 | planned |
| NAV-07 | Embedded videos from Beamer `\movie` (multimedia package). `Movie` annotations are found, the `/Movie` path is resolved relative to the PDF, and an `AVPlayer` is created. Playback is mirrored between presenter and presentation (shared player per URL). Local files and web files are supported, streaming is not. Loop and autoplay are not supported. Since macOS 27, PDFKit no longer exposes `/Movie` in `annotationKeyValues` ([SlidePilot-macOS#89](https://github.com/SlidePilot/SlidePilot-macOS/issues/89)); read it via CoreGraphics | `PDFPageView.swift:205-277`; `Views/ConnectedPlayer.swift:48-71` | `latex-support` | AVKit works on iPad; sandbox folder access needed (same as NAV-06) | `VideoPlayer` (AVKit) over the slide surface | P2 | planned |
| NAV-08 | Video player key presses are passed on to the window, so slide navigation keeps working | `ConnectedPlayer.swift:48` | – | Same | – | P2 | planned |
| NAV-09 | Timer auto-start on the first "next slide" per document (see TIME-05) | `AppDelegate.swift:527,539-545` | – | Same | – | P2 | planned |

## 3a. Pre-rendering

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| PRE-01 | Render cache. Old: `NSCache` keyed by (page, display mode), count limit 200; pages 0…200 rendered in the background on open (full mode only); ±50 pages around each requested page. Not user-configurable. New (ADR 0005): current + next first, neighborhood in the background, memory-based limit; final scope after measurement in Phase 1 | `Helpers/RenderCache.swift:60-135,178-228` | `pre-rendering` | Stricter memory budget on iPad | – | P2 | changed |
| PRE-02 | The cache also serves thumbnails and remote slide images | `ThumbnailNavigation.swift:318`; `Remote/RemoteController.swift:40-55` | – | Same | – | P2 | planned |

## 4. Timing

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| TIME-01 | Clock in the presenter window, top left, `HH:mm:ss` 24 h. The new app follows the user's locale (the old one ignored it, see DEF-09) | `Views/Time/ClockLabel.swift` | `timing` | Same | Custom `ClockLabel` → `Text(date, style: .time)` in a `TimelineView`, system font with `.monospacedDigit()` | P2 | changed |
| TIME-02 | Stopwatch mode (counts up from 00:00:00). Start/stop **S**, reset **R** | `Views/Time/TimingControl.swift`; `Controllers/TimeController.swift`; `AppDelegate.swift:704,712` | `timing` | Same | Custom time view → `Text` with `.monospacedDigit()`; start/stop/reset as toolbar buttons with SF Symbols | P2 | planned |
| TIME-03 | Timer mode (counts down from a set time, goes negative and is then shown as `- HH:MM:SS` in the overtime color (205,55,55)). Set the time with **T** (enabled only in timer mode) using an hours/minutes/seconds picker. Reset (**R**) goes back to the set time. No alert at zero | `TimingControl.swift:24-77`; `PresenterViewController.swift:302-322`; `Views/Time/TimeInterval+Extension.swift` | `timing` | Same | Alert with `NSDatePicker` → sheet/popover with a standard duration picker; overtime in system red | P2 | planned |
| TIME-04 | Mode switch via Moderator ▸ Mode ▸ Stopwatch / Timer. The mode is not saved and the app starts in stopwatch mode | `AppDelegate.swift:128,689-694` | `timing` | Same | Segmented `Picker` in the toolbar and a `Picker` in the menu | P2 | planned |
| TIME-05 | Auto-start: the timer starts on the first "next slide" (keyboard/menu) per document. Pressing Start/Stop manually disables auto-start. Remote, thumbnail and link navigation do not auto-start | `AppDelegate.swift:539-545`; `NavigationWindow.swift:18` | – | Same | – | P2 | planned |
| TIME-06 | Time display size: hidden / small (55 pt font, 13 % height) / normal (70 pt, default). UserDefaults `timeSize` 0/1/2. Set in the layout editor | `PresenterViewController.swift:96-136`; `PreferencesController.swift:89-114` | – | Same | `Picker` in Settings; Dynamic Type on iPad | P2 | planned |
| TIME-07 | Time is based on the wall clock so it does not drift (the old app counted 1-second ticks, see DEF-08) | `TimingControl.swift` | – | Same | – | P2 | changed |

## 5. Notes

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| NOTES-01 | Two notes modes: **Text** (rich-text notes per page) and **Split** (notes are half of each PDF page, Beamer "show notes on second screen"). Notes ▸ Notes Mode ▸ Text / Split | `AppDelegate.swift:582-587,749-783,883` | `notes` | Same | `Picker` in the Notes menu and toolbar | P3 | planned |
| NOTES-02 | Split position None / Right / Left / Bottom / Top (**⌥⌘0…4**). The notes view shows that half and the audience sees the other half. Page rotation is respected. Choosing Split while the position is None sets Right; choosing None switches to Text; choosing Text sets None | `DisplayController.swift:13-45`; `Views/Slide/PDFPageView.swift:38-87`; `AppDelegate.swift:548-575,749,774,783` | `notes`, `shortcuts` | Same | Menu `Picker` with SF Symbols | P3 | planned |
| NOTES-03 | PDF keyword detection: exact, case-sensitive `SP-Right`, `SP-Left`, `SP-Top`, `SP-Bottom` in the PDF Keywords set the split position and Split mode on open. A saved per-document setting wins over the keywords | `Helpers/PDFDocument+Extension.swift:14-31`; `AppDelegate.swift:331-335,356` | `notes` | Same | – | P3 | planned |
| NOTES-04 | Text notes editor: rich text (bold, italic, underline, alignment, lists, spacing; no images). White text on a dark background (0.17 gray), "Finish" button while editing; finish with **⌘↩** or by clicking outside. Undo is supported and cleared on page change | `Views/Notes/NotesTextView.swift:132-137`; `Views/Notes/NotesEditor.swift` | `notes` | `TextEditor` with `AttributedString`; Format menu → toolbar | Custom `NSTextView` styling → SwiftUI `TextEditor` with `AttributedString` and system formatting commands; system text colors in light/dark (not forced white on gray); standard Done button | P3 | planned |
| NOTES-05 | Font size **⌘+ / ⌘-** (±1 pt) applies to all pages of the document and marks it edited. Not saved as a preference | `Controllers/TextFormatController.swift`; `Helpers/NotesDocument.swift:141-148` | `notes` | Same | Standard Format ▸ Font ▸ Bigger/Smaller commands | P3 | planned |
| NOTES-06 | New / Open / Save notes: **⌘N / ⇧⌘O / ⌘S**. Open is limited to `.rtf`. Save writes to the existing URL or suggests `<pdf>-<localized "Notes">.rtf` | `AppDelegate.swift:592-614,790-849` | `notes` | Save to the companion file; RTF via export | `fileImporter` / `fileExporter` | P3 | changed |
| NOTES-07 | Unsaved changes: if the notes were saved before, they are saved automatically; otherwise the user is asked Save/Delete. Applies on quit, when opening another PDF and on New/Open Notes | `AppDelegate.swift:790-849` | – | Autosave into the companion file | Autosave; standard save dialog | P3 | changed |
| NOTES-08 | Auto-load on PDF open: `<pdf base name><sep><name>.rtf` with `<sep>` ∈ {`-`, `_`, space} and `<name>` ∈ {`notes`, `Notes`, `Notizen`}. The first match wins, Text mode is set and notes are shown | `AppDelegate.swift:361-381` | `notes` | Needs folder access (security-scoped). Verify in Phase 1 | – | P3 | planned |
| NOTES-09 | Legacy file format: each page starts with a line `#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-N`; on load, `#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-[0-9]*\n` splits the pages and numbers are ignored. Text before the first separator is dropped | `Helpers/NotesDocument.swift:85-105`; `Helpers/NSAttributedString+Extension.swift:34` | `notes` | Same parser | – | P3 | planned |
| NOTES-10 | **New:** notes live in one companion file per PDF (with drawings and per-document settings). Legacy RTF files (NOTES-08/09) are imported automatically. RTF export in the legacy format stays available | – | – | Same | – | P3 | changed |

## 6. Pointer

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| PTR-01 | Show/hide pointer (**C**). Hovering over the current slide in the presenter window moves the pointer on the presentation window (relative coordinates; outside 0…1 hides it). Works with notes shown | `PresenterViewController.swift:431-464`; `Views/Presentation/PointerDisplayView.swift:44-113` | `pointer` | Pointer hover (trackpad/mouse) **and** touch drag / Apple Pencil hover | – | P3 | planned |
| PTR-02 | Pointer appearances (**⌘1…⌘7**): Cursor, Hand, Dot, Circle, Target Black, Target Red, Individual | `DisplayController.swift:58-60`; `Main.storyboard:501-532` | `pointer`, `shortcuts` | Cursor/Hand used `NSCursor` images; iPad needs own artwork | Menu `Picker` with SF Symbols, also as toolbar menu | P3 | planned |
| PTR-03 | Presets: Target (size 44, thickness 3, black, 2 px white border); Target Red (44/3, red, no border); Circle (20/3, white, shadow 10); Dot (10, black, 5 px white border, shadow 10); Cursor and Hand are system cursor images with hotspot handling | `Views/Presentation/PointerView.swift:74-79,145-417` | – | Same values | Custom pointer overlay (allowed: pointer overlay) | P3 | planned |
| PTR-04 | Pointer editor (Individual, **⌃⌥C**, opens the Pointer settings pane): shapes target, dot, circle, plus, cross, square; sliders for size, thickness, border width, shadow; color and border color with alpha; live preview. Ranges: target size 35–150 (default 44), thickness 2–50 (3); other shapes size 5–100; dot and square have no thickness; border and shadow 0–50 | `Views/Presentation/PointerEditorViewController.swift:36-218`; `PointerView.swift:14-71` | `pointer` | Sheet | Custom preference pane → `Form` (Settings scene / sheet) with `Picker` for shape, `Slider`s, `ColorPicker` with opacity and a live preview | P3 | planned |
| PTR-05 | Custom pointer stored globally in UserDefaults `individualPointerKey` (JSON). Default: Target. Colors must be stored platform-neutrally (RGBA), not as archived `NSColor` | `DisplayController.swift:102-118` | – | Shared format | – | P3 | changed |
| PTR-06 | Over the presentation window itself the mouse cursor is replaced by the pointer image | `PointerDisplayView.swift` | – | n/a | Pointer overlay with a custom cursor (allowed: pointer overlay) | P3 | planned |
| PTR-07 | Pointer display state and appearance are part of the per-document settings (SET-02) | `ConfigurationController.swift` | `customize-layout` | Same | – | P3 | planned |

## 7. Drawing

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| DRAW-01 | Draw on the current slide (**D**, close with **Esc** or the toolbar Close button). Only the presenter's current slide is editable; the presentation window, next-slide preview and thumbnails show the drawing read-only | `DisplayController.swift:345-367`; `SlideArrangementView+ViewSetup.swift:280-297`; `PresentationViewController.swift:88-101` | `drawing` | Apple Pencil + finger | Custom drawing layer (allowed). iPad: evaluate PencilKit `PKCanvasView` + `PKToolPicker` | P3 | planned |
| DRAW-02 | One drawing per page. Points are stored relative to the page; half-page sections are handled when split notes are shown. Fixed line width 2 pt | `Views/Drawing/Drawing.swift:11-205`; `Views/Drawing/CanvasView.swift:30-111` | – | PencilKit may be considered; must keep the relative model | – | P3 | planned |
| DRAW-03 | Floating drawing toolbar at the bottom: 6 colors (black, white, blue, green, magenta, orange; RGB values in `DrawingToolbar.swift:23-38`), Eraser (= clear all strokes, no stroke eraser), transparent canvas, white canvas, Close | `Views/Drawing/DrawingToolbar.swift:23-247` | `drawing` | Same | Custom floating toolbar with color swatch and icon buttons → standard toolbar: color `Picker` with the preset colors + `ColorPicker`, SF Symbol buttons (eraser, canvas, done). iPad: `PKToolPicker` | P3 | planned |
| DRAW-04 | Canvas background: transparent (**⌃K**, "Clear Canvas") or white (**⌃⇧K**, "White Canvas"). Switching the background clears the strokes. Clear Drawings (**⌃C**) clears the strokes | `Controllers/CanvasController.swift:13-55`; `CanvasView.swift:139-148`; `Main.storyboard:314-335` | `drawing` | Same | `Commands` items + toolbar `Picker` for the canvas background | P3 | planned |
| DRAW-05 | Drawing mode locks layout changes and disables all Notes menu items | `DisplayController.swift:345-367`; `AppDelegate.swift:979-984` | `drawing` | Same | – | P3 | planned |
| DRAW-06 | Setting "Save drawings" (UserDefaults `saveDrawings`, default off). Off: drawings are deleted when leaving draw mode and slide switching is blocked while drawing. On: drawings are kept in memory across slide changes and slides can be switched while drawing. Turning it off deletes all drawings | `PreferencesController.swift:19,131-143`; `GeneralPreferencesViewController.swift:53-55` | `drawing` | Same | `Toggle` in Settings | P3 | planned |
| DRAW-07 | **New:** when "Save drawings" is on, drawings are persisted in the companion file and survive auto-reload (old app: memory only, wiped on reload, see DEF-06) | `Controllers/DocumentController.swift:18,40-47,118-128` | – | Same | – | P3 | changed |
| DRAW-08 | Undo/redo per stroke, clear and background change (**⌘Z / ⇧⌘Z**). The undo stack is cleared when leaving draw mode | `CanvasView.swift:119-135` | – | Same | System `UndoManager` (Edit menu, iPad undo gestures) | P3 | planned |
| DRAW-09 | The canvas is hidden on the presentation window while a curtain is shown | `PresentationViewController.swift:138-159` | – | Same | – | P3 | planned |
| DRAW-10 | Export drawings (**⇧⌘S**, File ▸ Export Drawings): a copy of the PDF with one ink annotation per stroke, crop box reset to media box. Default name `<pdf>-<localized "Drawings">.pdf`. The new app exports the white background and the real line width (see DEF-05) | `Helpers/DrawingsExporter.swift:25-79`; `AppDelegate.swift:455-504` | `drawing` | Share sheet / file exporter | `fileExporter`; iPad: `ShareLink` | P3 | changed |

## 8. Curtain

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| CUR-01 | Black curtain (**B**, hidden alternate **.**) and white curtain (**W**) toggle a full black/white cover on the presentation window. Black and white are mutually exclusive; pressing the same key again hides the curtain | `DisplayController.swift:48-50,155-223`; `Main.storyboard:469-487` | `curtain` | Same | `Commands` + toolbar buttons with SF Symbols; the curtain itself is part of the slide surface | P2 | planned |
| CUR-02 | While a curtain is shown, the presenter shows a "Hidden Screen" warning banner | `PresenterViewController.swift:224-299`; `Views/UserNotice.swift` | – | Same | Custom `UserNotice` banner → standard `Label` with an SF Symbol in the presenter toolbar/status area | P2 | planned |
| CUR-03 | Curtain state is not persisted | – | – | – | – | P2 | planned |

## 9. Settings

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| SET-01 | Settings window with panes General, Layout, Pointer, Remote (**⌘,**) | `Views/Preferences/Preferences+PaneIdentifiers.swift` | – | Settings sheet inside the app | Third-party Preferences package → `Settings` scene with `TabView` (macOS); sheet with `Form` (iPad) | P4 | planned |
| SET-02 | Per-document settings: notesPosition, notesMode, isNavigatorDisplayed, isPointerDisplayed, pointerAppearance (+ custom configuration). Saved when another PDF is opened and on quit; loaded at the end of opening (overrides PDF keywords). Not saved: page, timer, layout, font size. The new app stores them in the companion file | `Controllers/ConfigurationController.swift:14-59`; `DisplayController.swift:510-569`; `AppDelegate.swift:154,312,356` | `customize-layout` | Same | – | P3 | changed |
| SET-03 | Per-document settings expire **4 weeks (28 days)** after the document was last opened. Cleanup at launch. (The old app measured from the last save, see DEF-10) | `ConfigurationController.swift:17-34` | `customize-layout` | Same | – | P3 | planned |
| SET-04 | Keep the display awake (UserDefaults `isSleepDisabled`, default off) via an IOPM `NoDisplaySleep` assertion while the app runs | `Helpers/AwakeManager.swift`; `PreferencesController.swift:35-67` | – | `isIdleTimerDisabled` | `Toggle` in Settings | P2 | planned |
| SET-05 | General pane: Keep awake, Crossfade slides, Save drawings | `Views/Preferences/GeneralPreferencesViewController.swift` | `drawing` | Same | `Form` with `Toggle`s | P4 | planned |
| SET-06 | Help menu item (**⌘?**) opens the online docs | `AppDelegate.swift:163` | – | Link in settings | Standard Help menu (`CommandGroup(replacing: .help)`) | P5 | planned |

## 10. Remote (ships with 1.1)

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| REM-01 | Remote control from an iPhone app. **New protocol** (Network framework, Bonjour, encrypted connection keyed from pairing, Codable messages); not compatible with the old SlidePilot Remote app (ADR 0006) | `Remote/RemoteService.swift` (MultipeerConnectivity, service `slidepilot-ctrl`) | `remote` | iPad acts as host as well | – | P4 | changed |
| REM-02 | Discovery list in Settings ▸ Remote; Connect; pairing code shown on both devices and confirmed; device becomes trusted and reconnects automatically when both apps are active | `RemoteService.swift:192-211,314-364`; `Views/Preferences/RemoteVerificationViewController.swift` | `remote` | Same | `Form` with a device `List`; pairing code in an alert/sheet | P4 | planned |
| REM-03 | Trusted devices: list and remove (Trusted Devices sheet). Disconnect button (also removes trust) | `Views/Preferences/TrustedDevicesViewController.swift:27-47` | `remote` | Same | `List` with swipe-to-delete / Delete button | P4 | planned |
| REM-04 | Host → phone: current slide, next slide (black at the end), notes slide (split mode), notes text, meta (slide number, slide count, curtain state). Sent on page change, document open, notes position change, curtain change, notes edit and when a device connects | `Remote/RemoteController.swift:23-87,153-159` | `remote` | Same | – | P4 | planned |
| REM-05 | Phone → host: next/previous slide, black/white/hide curtain, pointer position and pointer finish | `RemoteService.swift:151-185`; `RemoteController.swift:194-206` | `remote` | Same | – | P4 | planned |
| REM-06 | Only verified devices may send commands and receive content (the old app did not check this, see DEF-04) | `RemoteService.swift:151-185` | – | Same | – | P4 | changed |
| REM-07 | iPhone remote app UI: swipe to change slides, pinch to zoom, curtain button (long press for black/white), double tap + hold + drag for the pointer, layout button, progress button | separate repo (not in reference) | `remote` | – | Standard iOS components (separate work) | P4 | planned |

## 11. Localization

| ID | Feature | Old source | Docs | iPad notes | Native replacement | Milestone | Status |
|---|---|---|---|---|---|---|---|
| L10N-01 | Languages English (development), German, French in a String Catalog | `en.lproj`, `de.lproj`, `fr.lproj` (53 keys each in `Localizable.strings`, plus storyboard and xib strings) | `master` | Same | String Catalog (`Localizable.xcstrings`) | P4 | planned |
| L10N-02 | All old UI texts are translated; existing translations are reused as a starting point | `*/Localizable.strings`; `*/Main.strings`; xib `.strings` | – | Same | – | P4 | planned |

## 12. Dropped or deferred

| ID | Feature | Old source | Reason | Status |
|---|---|---|---|---|
| DROP-01 | Touch Bar (curtains, notes, navigator, next-slide preview, draw, pointer + appearance popover; in draw mode: colors, eraser, close) | `Views/TouchBar/*` | Product-owner decision 2026-11-10 | dropped |
| DROP-02 | Sparkle updater (Check for Updates…) | `Sparkle.framework`; `Info.plist:52-55` | App Store distribution (ADR 0003) | dropped |
| DROP-03 | Donation alert after the 5th launch (`AppStartCount`, `AlreadyDisplayedDonationAlert`). Replaced by an App-Store-compliant hint or tip jar **in the free Mac app only**, never in the paid iPad app. Form decided before Phase 5 | `Helpers/AppStartTracker.swift`; `PresenterViewController.swift:143-162` | App Store rules; pricing model (ADR 0003) | changed |

---

## Keyboard shortcuts

Source: `Base.lproj/Main.storyboard` and the key handlers listed. "Plain" means no modifier. Plain-letter shortcuts must not fire while a text field (notes editor, navigator page field) has focus.

| Menu | Command | Shortcut | ID |
|---|---|---|---|
| SlidePilot | Settings… | ⌘, | SET-01 |
| File | Open… / Close | ⌘O / ⌘W | DOC-01 |
| File | Export Drawings | ⇧⌘S | DRAW-10 |
| Edit | Undo / Redo / Cut / Copy / Paste / Paste and Match Style / Select All | ⌘Z / ⇧⌘Z / ⌘X / ⌘C / ⌘V / ⌥⇧⌘V / ⌘A | – |
| Format | Bold / Italic / Underline | ⌘B / ⌘I / ⌘U | NOTES-04 |
| Format | Bigger / Smaller | ⌘+ / ⌘- | NOTES-05 |
| Format | Align Left / Center / Right | ⌘{ / ⌘\| / ⌘} | NOTES-04 |
| Format | List… / Spacing… | ⌘L / ⌃⌘S | NOTES-04 |
| View | Enter Full Screen | ⌃⌘F | DOC-05 |
| Moderator | Edit Layout | ⌃⌥L | LAY-04 |
| Moderator | Show Navigator | O (plain), close: Esc | LAY-06 |
| Moderator | Show Current Slide | A (plain) | LAY-02 |
| Moderator | Preview Next Slide | P (plain) | LAY-02 |
| Moderator | Set Timer | T (plain) | TIME-03 |
| Moderator | Start/Stop Time | S (plain) | TIME-02 |
| Moderator | Reset Time | R (plain) | TIME-02 |
| Moderator | Draw | D (plain), close: Esc | DRAW-01 |
| Moderator | Clear Drawings | ⌃C | DRAW-04 |
| Moderator | Clear Canvas (transparent) | ⌃K | DRAW-04 |
| Moderator | White Canvas | ⌃⇧K | DRAW-04 |
| Notes | Show Notes | N (plain) | LAY-02 |
| Notes | Split Position None / Right / Left / Bottom / Top | ⌥⌘0 / ⌥⌘1 / ⌥⌘2 / ⌥⌘3 / ⌥⌘4 | NOTES-02 |
| Notes | New / Open / Save Notes | ⌘N / ⇧⌘O / ⌘S | NOTES-06 |
| Notes editor | Finish editing | ⌘↩ | NOTES-04 |
| Presentation | Previous / Next Slide | ← ↑ PageUp / → ↓ PageDown; hidden: ⌃⌘← / ⌃⌘→ | NAV-01, NAV-02 |
| Presentation | Go Back | ⌃G | NAV-03 |
| Presentation | Black Screen | B (plain), hidden: . | CUR-01 |
| Presentation | White Screen | W (plain) | CUR-01 |
| Presentation | Show Pointer | C (plain) | PTR-01 |
| Presentation | Pointer Appearance Cursor … Individual | ⌘1 … ⌘7 | PTR-02 |
| Presentation | Edit Pointer | ⌃⌥C | PTR-04 |
| Help | SlidePilot Help | ⌘? | SET-06 |

---

## Inconsistencies found

1. **Shortcuts page lists ⌃⌥L for both "Edit Layout" and "Edit Pointer".** In the code, Edit Pointer is **⌃⌥C**. There is no duplicate binding in the code. → Use the code; fix the docs later.
2. **Docs call ⌃K "Canvas Mode".** In the code ⌃K sets the transparent canvas ("Clear Canvas") and ⌃⇧K the white canvas. The menu names "Clear Canvas" and "Clear Drawings" are easy to confuse. → Keep the bindings, choose clearer menu titles.
3. **Undocumented shortcuts:** `.` (black curtain), ⌃⌘←/→ (slide change, documented only as "while editing notes"), Esc in the navigator and in draw mode, ⌃⇧K.
4. **"Save drawings" is documented as saving drawings**, but the old app only keeps them in memory for the session. → DRAW-07 makes it persistent.
5. **Pre-rendering docs** say "the surrounding 50 pages … i.e. 100 pages". The code queues ±50 pages around the requested page, plus pages 0…200 (201 pages) at open, in full-page mode only. The cache limit is a 200-entry `NSCache` count limit (soft). → New design per ADR 0005.
6. **4-week expiry:** docs and code comment say "after last opening", the code uses the last save time.
7. **Curtain docs** say the curtain is shown "on the Presenter Window"; it is the presentation window.
8. **Donation alert:** the code comment says "third start", the code shows it from the 5th start.
9. **Docs list English and German** ("French will follow"); the app ships French as well.
10. **Docs say macOS 10.13+**; the project sets 10.11 (target) / 10.15 (project).
11. **Old Apple team mismatch:** the app target and the test target use different development teams.
12. **Stale files:** `de.lproj/Main.storyboard` and `fr.lproj/Main.storyboard` are old copies not referenced by the project. `de.lproj/Main.strings` lacks the "File" menu title.
13. **Swapped assets:** `BlackCurtain.imageset` contains the white curtain images and vice versa (Touch Bar only).
14. **Plain-letter shortcuts** have no `validateMenuItem`, so they may fire while typing in the notes editor or navigator field.

## Known defects – do not replicate

| ID | Defect in the old app | Old source |
|---|---|---|
| DEF-01 | Set Timer: Cancel still applies the entered time | `PresenterViewController.swift:317` |
| DEF-02 | Render cache changes the shared `PDFPage` crop box from background threads (breaks link hit-testing in split mode); cancelling queued work has no effect; `NSImage(size:flipped:drawingHandler:)` is lazy, so nothing is actually pre-rendered | `Helpers/RenderCache.swift:102,178,222,228` |
| DEF-03 | Launch order: pointer and timer mode are reset in `applicationDidFinishLaunching`, possibly after `openFile:` already applied the per-document settings | `AppDelegate.swift:111,128` |
| DEF-04 | Remote accepts commands from unverified devices and sends slides to them; a remote-initiated disconnect removes trust; 4-digit code confirmed only on the Mac | `Remote/RemoteService.swift:151-211` |
| DEF-05 | Drawing export ignores the white background, uses 1.0 pt instead of 2.0 pt, and shows a failure alert when the save panel is cancelled | `Helpers/DrawingsExporter.swift:58`; `AppDelegate.swift:500-502` |
| DEF-06 | Auto-reload wipes all drawings; watching stops after an atomic save (rename/replace) | `DocumentController.swift:40-47`; `FileObserver.swift` |
| DEF-07 | Video embedding: `return` instead of `continue` stops at the first bad annotation; visibility check is always true; video frame ignores letterboxing | `PDFPageView.swift:218-259` |
| DEF-08 | Stopwatch/timer drift (tick counting); switching mode clears the timer value | `TimingControl.swift:24-31` |
| DEF-09 | Clock ignores the user's locale and creates a `DateFormatter` every second | `ClockLabel.swift` |
| DEF-10 | Per-document expiry measured from last save instead of last open | `ConfigurationController.swift:17-34` |
| DEF-11 | A notes file that fails to load leaves the previous PDF's notes in place | `AppDelegate.swift:344-349` |
| DEF-12 | Notes saving forces black text and passes `.html` as document type for RTF; adjacent separators can produce a negative range | `NotesDocument.swift:103-105`; `NSAttributedString+Extension.swift:34` |
| DEF-13 | Font size change drops bold/italic on the displayed page | `TextFormatController.swift` |
| DEF-14 | Pointer editor resets all sliders when the shape changes; remote pointer is shown even when the pointer is hidden | `PointerEditorViewController.swift:155-158`; `RemoteController.swift:194-199` |
| DEF-15 | Next-slide canvas uses the current page's size; a missing section aborts drawing all remaining lines | `Views/Slide/SlideArrangementView.swift:142`; `CanvasView.swift:65` |
| DEF-16 | `showSlide` returns early when the layout has no current slide, so next/notes may not update | `SlideArrangementView.swift:132-133` |
| DEF-17 | Opening an unreadable PDF fails silently after the windows are set up | `AppDelegate.swift:309-315` |
