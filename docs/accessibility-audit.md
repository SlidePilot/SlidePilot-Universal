# Accessibility audit (WCAG 2.2 AA)

Audit for issue #72 before the 2.0 release: the finished app on macOS 26 and iPadOS 26 against WCAG 2.2 level AA, applied to native apps as described in [WCAG2ICT](https://www.w3.org/TR/wcag2ict-22/). The slides themselves are out of scope (they come from the presenter's PDF).

## Method
- **Code review** of every view for labels, values, traits, fixed sizes, colors, animations and custom hit areas.
- **Mac:** the test build driven through the SlidePilot Test Host (ADR 0018). The accessibility tree of the presenter window (with and without the navigator, in draw mode) and the Settings window was read with `scripts/mac-test-host.py tree`; that is the tree VoiceOver and Full Keyboard Access use.
- **iPad:** iPad Pro 11-inch (M5) simulator, iPadOS 27.2, German UI, `links.pdf` fixture: portrait and landscape, light and dark, Increase Contrast, the largest accessibility text size (AX5), hardware keyboard.
- **Contrast** of the only custom colors (timer warnings) computed from their sRGB values; everything else uses system colors and materials.
- Not possible here: VoiceOver speech itself, Voice Control, Switch Control, Full Keyboard Access on a real device, the Accessibility Inspector app, and Differentiate Without Color in the simulator. These are listed under [Manual checks](#manual-checks).

## Results

| Criterion | Result | Notes |
|---|---|---|
| 1.1.1, 4.1.2 Name, role, value | Pass after fixes | Slides read "Current slide, n of count", "Next slide, …", "Presentation, slide n of count"; slot titles are headings; timer and clock have spoken values; toggles report On/Off. Fixed: draw-mode tools on the Mac, page number field (see below). |
| 1.3.1, 2.4.3 Info and relationships, focus order | Pass | Mac tree order: navigator (page field, thumbnails), time, current slot, next slot, notes, toolbar. iPad follows the same layout order. Settings use grouped forms with section headers. |
| 1.3.4 Orientation | Pass | iPad presenter works in portrait (slots stacked) and landscape (side by side). |
| 1.4.1 Use of color | Pass after fix | Overtime has its minus sign; warning stages are spoken in the timer's value. Fixed: with Differentiate Without Color the warnings show one or two exclamation marks. Pen and pointer colors have names in VoiceOver and in the color list. The current thumbnail has a frame and the selected trait. |
| 1.4.3, 1.4.11 Contrast | Pass | System colors adapt to Increase Contrast. Timer colors on the window background (the timer is at least 27 pt, so 3:1 applies): orange 4.6:1 light / 10.2:1 dark (asset color with Increase Contrast variants, 6.2:1 / 11.8:1), purple 4.1:1 / 6.0:1, red 3.6:1 / 6.2:1. |
| 1.4.4 Resize text | Pass | At AX5 all chrome text grows; the time display scales relative to Large Title and shrinks instead of truncating; the toolbar moves items into its overflow menu; settings rows wrap. Notes keep their stored size by design (NOTES-05): the presenter enlarges them with Format ▸ Font ▸ Bigger (⌘+, also in the iPad menu bar), up to 200 pt. Decision 2026-11-25: keep it that way. |
| 1.4.10 Reflow, 1.4.12 Text spacing | Pass | Standard text views and forms; no fixed-height text containers. |
| 2.1.1, 2.1.2 Keyboard, no trap | Pass | Every command is in the menu bar (Mac, iPad) with the old app's shortcuts; arrow keys change slides; Esc leaves draw mode, the navigator and notes editing. No custom focus handling that traps focus. |
| 2.2.1, 2.2.2 Timing | Pass | The timer never ends an action; nothing moves on its own except the clock and timer. |
| 2.3.1 Flashes | Pass | No flashing content. |
| 2.3.3 Animation (AAA, checked anyway) | Pass after fix | Slide crossfade and video fade-in are off with Reduce Motion (LAY-07, NAV-07). Fixed: the navigator no longer animates its scroll with Reduce Motion. |
| 2.4.6, 2.4.7 Labels, focus visible | Pass | System focus rings and hover effects; the navigator page field shows the system focus. |
| 2.5.8 Target size | Pass | iPad toolbar items, list rows and the color list (50 pt rows) are at least 44 pt; the split separator has a 45 pt touch area around its 1 pt line. Link areas come from the PDF (out of scope). |
| 3.3.1 Error identification | Pass | Broken or non-PDF files, missing folder access, import and pairing errors use system alerts or `ContentUnavailableView` with a description, which VoiceOver reads. |
| Reduce Transparency | Pass | Only system materials and Liquid Glass of standard components (and `glassEffect` on the page field), which follow the setting. |
| Timer cues (2.2.1 / 2.3.1 of the issue) | Pass after fix | New: VoiceOver announces "First warning", "Second warning" and "Overtime" when the running timer reaches them, so the color change is not the only cue. |

## Fixes in this PR
- **Mac draw-mode tools:** the toolbar item holding Draw, Color, Clear Drawings and White Canvas gave every control the name "Draw". It now has its own accessibility container; each control has its own name.
- **Navigator page field:** the plain text field had no accessible name on the Mac (only its prompt). It is now "Page Number".
- **Timer warnings without color:** one exclamation mark for the first warning, two for the second, while Differentiate Without Color is on.
- **Timer announcements:** VoiceOver says when a warning or overtime starts.
- **Navigator scroll:** no scroll animation with Reduce Motion.

## Known limitations
- **Mac split buttons** (Start Time, Curtain): AppKit names the main segment after its symbol ("play", "rectangle"). The button itself carries the right name and help text; setting a label on the icon does not reach the segment. A system behavior; no app-side fix found.
- **Notes text size** does not follow Dynamic Type (see 1.4.4); this is the approved NOTES-05 behavior.

## Follow-ups
- #193: automated `performAccessibilityAudit` in an iPad UI test (needs an ADR for the XCTest exception; cannot run on the Mac outside the test host).

## Manual checks
Before the release, on real devices:
1. **VoiceOver (Mac and iPad):** present `links.pdf`: slide changes are announced, slide links appear as VoiceOver actions, the timer announces its warnings.
2. **Voice Control and Switch Control (iPad):** open a PDF, start the presentation on an external display, change slides, show the curtain, draw.
3. **Full Keyboard Access (Mac and iPad):** Tab reaches the toolbar, navigator and notes; no trap.
4. **Differentiate Without Color:** set a 1-minute timer with warnings at 1 min; the timer shows the exclamation marks.
5. **Accessibility Inspector audit** on the Mac presenter, presentation and Settings windows.
6. **App Store Accessibility Nutrition Labels:** fill in App Store Connect for macOS and iPadOS. Supported, based on this audit and once checks 1–3 pass: VoiceOver, Voice Control, Larger Text (not the notes body, see above), Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion. Not applicable: Captions and Audio Descriptions (the app plays only the presenter's own videos).
