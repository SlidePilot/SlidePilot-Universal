# UI and usability review (#107)

A review of the finished app on macOS 26, iPadOS 26 (iPad Air 13-inch) and iOS 26 (iPhone 17) against the Human Interface Guidelines and [ADR 0010](decisions/0010-native-design-first.md) (native design first). It covers toolbars, menus, settings, empty and error states, wording in en, de and fr, and light and dark mode. Accessibility is covered separately in #72.

The screenshots are attached to the PR that added this file (fixtures only). Mac screens come from the app-rendered snapshots, because the test host was busy with another session.

**Ranking:** high = users can get stuck or are misled; medium = inconsistent or harder to find than needed; low = polish.
**Status:** *fixed* = changed in the review PR; *proposal* = waits for the maintainer's decision; accepted proposals become their own issues.

## Fixed in the review PR

| Rank | Screen | Problem | Change |
|---|---|---|---|
| medium | Settings (all) | The "Remote" tab and page title were not translated in de and fr. | "Fernsteuerung" / "Contrôle à distance", as in "Remote Control" elsewhere. |
| medium | Mac and iPad menu bar (fr) | The "Moderator" menu was not translated in fr. | "Modérateur", the old app's fr name. |
| low | Import of a .slidepilot file | The message named the setting "Save Drawings" (en) and „Zeichnungen sichern“ (de); the setting is "Save drawings" / „Zeichnungen speichern“. | The message uses the setting's exact name. |
| low | Layout menu (fr) | "Afficher la diapositive courante"; everywhere else "actuelle". | "actuelle". |
| low | Curtain (fr) | Straight apostrophes in three strings; the rest of the catalog uses ’. | Typographic apostrophes. |

| low | Remote settings (Mac) | "…choose File ▸ Control Another Device…." ended with "…." (P12). | The ellipsis is dropped in running text. |

None of these changes parity behavior.

## Decisions (2026-11-25)

| # | Decision | Where |
|---|---|---|
| P1 | Accepted. | #206 |
| P2 | Changed: remove Moderator ▸ Edit Layout… (⌃⌥L) and Edit Pointer… (⌃⌥C) altogether; both only open a Settings tab, which Settings already reaches. | #206 |
| P3 | Accepted. | #206 |
| P4 | Rejected. | – |
| P5 | Keep "Moderator". | – |
| P6 | Accepted as: move Go Back to the overflow menu in iPad portrait. | #207 |
| P7 | Rejected. | – |
| P8 | Accepted. | #207 |
| P9, P10, P11 | Rejected. | – |
| P12 | Accepted, fixed in the review PR. | #208 |
| – | Added: move the two timer warnings from Settings ▸ Layout into the Time menu, next to Set Timer and Turn Off Timer. | #206 |
| – | Bug found by the maintainer: no color selection while drawing on iPhone. | #207 |

## Proposals

### Presenter (all platforms)

| # | Rank | Problem | Suggested change | Parity |
|---|---|---|---|---|
| P1 | medium | An empty notes slot is a blank box with no hint. New users don't see that they can type there or import notes. | Show a placeholder in the empty editor ("Add notes for this slide") and, in the Notes slot of a document without any notes, a hint to File ▸ Import Notes… . | New UI, no behavior change. |
| P2 | medium | Moderator ▸ Edit Layout… (⌃⌥L) opens Settings ▸ Layout, which holds padding, time display size and timer warnings, not the arrangement. Users looking for layouts find them in the toolbar's Layout menu instead. | Rename the menu item to "Layout Settings…", so it says what it opens. | Changes the old menu title (LAY-04); the shortcut table and SET-01 need the new title too. |
| P3 | medium | In iPad portrait the two columns stack top and bottom (`PresenterSplit.stacksVertically`), but the Layout menu still calls the slots "Left" and "Right". | Name the places by orientation ("Top" / "Bottom") while the split is stacked. | Changes the LAY-04 note on slot names in stacked windows; needs a parity-doc update. |
| P4 | low | Notes mode "Split" (de „PDF spalten“) does not say what is split. | "Split PDF Page" / „PDF-Seite teilen“ / « Scinder la page PDF ». | Wording only. |
| P5 | low | The menu is named "Moderator" in en, while the rest of the app says "presenter" (Presenter window, presenter display). | Keep "Moderator" (old app, users know it) or rename to "Presenter". Recommended: keep. | Old menu name. |

### iPad

| # | Rank | Problem | Suggested change | Parity |
|---|---|---|---|---|
| P6 | low | In portrait on the 13-inch iPad the toolbar truncates the document title ("plain-sli…"). | Let the title go to the overflow first, or move Go Back to the overflow in portrait. | No. |
| P7 | low | The black pen-color swatch is barely visible on the dark toolbar in dark mode; its `.separator` hairline is too faint. | Use a stronger semantic stroke around the swatch. | No. |

### iPhone

| # | Rank | Problem | Suggested change | Parity |
|---|---|---|---|---|
| P8 | high | In portrait, Draw lands in the overflow menu although Time, Curtain and Draw were meant to stay in the bar (#189). The pointer tip, the large time display and the notes leave little room for the slide. | Fix the compact toolbar so Draw stays in the bar; let the time display shrink on compact height. Follow-up to #189 and #99. | No. |
| P9 | medium | In compact width (iPhone, narrow iPad windows) the navigator button uses `rectangle.grid.1x2`, which resembles the layout options (`rectangle.split.2x1`); regular width uses `sidebar.left`. | Use `list.bullet.rectangle` in compact width, where the navigator is a sheet, not a sidebar. | No. |
| P10 | low | The pointer tip covers about a third of the landscape screen until it is closed. | Show it only after the first double-tap on the slide fails, or as a popover tip anchored to the slide. | No. |

### Launch and document browser (iPad, iPhone)

| # | Rank | Problem | Suggested change | Parity |
|---|---|---|---|---|
| P11 | low | The launch scene is the plain default (app name, Create/Open). | Add the app's accent background and a short subtitle ("Present LaTeX Beamer PDFs"). | No. |

### Wording (en)

| # | Rank | Problem | Suggested change |
|---|---|---|---|
| P12 | low | "…choose File ▸ Control Another Device…." ends with "…." | Drop the ellipsis in running text ("choose File ▸ Control Another Device."). |

## Cross-platform consistency

- **Wording:** the same commands use the same titles on Mac and iPad (Layout, Time, Curtain, Draw, Import and Export). Exceptions: the navigator symbol in compact width (P9) and "Moderator" (P5), which exists only in the Mac and iPad menu bars.
- **Placement:** Layout sits next to Start Presentation on the Mac and with Import/Export and Settings on iPad and iPhone; both follow the decision in #189. Settings are a window on the Mac and a sheet on iPad and iPhone, as the platforms expect.
- **Shortcuts:** the Mac and iPad menus share all shortcuts (plain letters for the timer, ⌥⌘0…4 for split position, ⌃⌥L for layout settings). The iPhone has no menu bar; every command is reachable from the toolbar or its overflow menu.
- **Icons:** all from SF Symbols; only the compact-width navigator symbol differs (P9).

## Discoverability

| Feature | Mac | iPad | iPhone | Note |
|---|---|---|---|---|
| Layouts | Toolbar ▸ Layout, View menu | Toolbar ▸ Layout | Overflow ▸ Layout | Good; slot names in portrait see P3. |
| Notes | Layout ▸ Show Notes, then type | Same | Same | Empty slot gives no hint (P1). Import is in File ▸ Import Notes… / Import and Export. |
| Drawing | Toolbar ▸ Draw, Moderator menu | Toolbar ▸ Draw | Overflow in portrait (P8) | Tool picker decision in #101. |
| Pointer | Toolbar ▸ Pointer | Tip explains the double-tap | Tip explains the double-tap | Tip is large on iPhone (P10). |
| Remote | File ▸ Control Another Device…, Settings ▸ Remote | Document browser, Settings | Document browser, Settings | Empty states explain what to do on the other device. |

## What looked right

- Toolbar groups and overflow sections on all three platforms, light and dark.
- Time menu, Layout menu structure and the settings structure (General inline, Layout, Pointer, Remote, Stored Document Data, Help).
- Empty and error states of the remote screens, the external display hint and "Ready to Present" use `ContentUnavailableView`.
- iPhone landscape: current slide and notes side by side.
- All 340 catalog strings have de and fr.
