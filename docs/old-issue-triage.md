# Triage of the old app's open issues

Before the 2.0 release, every open issue of [SlidePilot-macOS](https://github.com/SlidePilot/SlidePilot-macOS/issues) was checked against the rewrite ([#85](https://github.com/SlidePilot/SlidePilot-Universal/issues/85)). State of the old repository on 2026-11-24: 23 open issues (1 bug, 22 feature requests and improvements). Decisions on new features were made by the product owner on 2026-11-25.

**Categories**
- **Bug, avoided:** a defect of the old app that the rewrite does not have; listed under "Known defects – do not replicate" in [feature-parity.md](feature-parity.md).
- **Solved by the rewrite:** the request is covered by an existing parity item or design decision.
- **Obsolete:** no longer applies to the rewrite or needs nothing from the app.
- **Request:** new feature or change beyond parity; the decision says whether it ships in 2.0, 2.1 or not at all.

| Old issue | Topic | Category | Decision | New issue |
|---|---|---|---|---|
| [26](https://github.com/SlidePilot/SlidePilot-macOS/issues/26) | Export PDF and notes together | Solved by the rewrite | The `.slidepilot` file carries notes, drawings and settings (NOTES-11); the PDF is deliberately not embedded | – |
| [29](https://github.com/SlidePilot/SlidePilot-macOS/issues/29) | Neutral desktop picture while presenting | Request | Not at all: changing the user's desktop picture is too invasive, and the rewrite shows the presentation or a ready screen on a connected display at once (DOC-05) | – |
| [51](https://github.com/SlidePilot/SlidePilot-macOS/issues/51) | Search slide text in the navigator | Request | 2.1 | [#169](https://github.com/SlidePilot/SlidePilot-Universal/issues/169) |
| [54](https://github.com/SlidePilot/SlidePilot-macOS/issues/54) | Draw in the presentation window | Request | Not at all: tools there would be visible to the audience, and the iPad's external display takes no input; drawing stays on the presenter (DRAW-01) | – |
| [55](https://github.com/SlidePilot/SlidePilot-macOS/issues/55) | Beamer overlays: page labels, skip build steps | Request | 2.1 | [#167](https://github.com/SlidePilot/SlidePilot-Universal/issues/167) |
| [59](https://github.com/SlidePilot/SlidePilot-macOS/issues/59) | Automatic slideshow with loop | Request | Not at all: kiosk use, not a presenter feature | – |
| [60](https://github.com/SlidePilot/SlidePilot-macOS/issues/60) | Show the elapsed time to the audience | Request | Not at all; the break countdown ([#173](https://github.com/SlidePilot/SlidePilot-Universal/issues/173)) covers the audience-facing time | – |
| [62](https://github.com/SlidePilot/SlidePilot-macOS/issues/62) | Laser pointer with fading strokes | Request | 2.0 | [#165](https://github.com/SlidePilot/SlidePilot-Universal/issues/165) |
| [64](https://github.com/SlidePilot/SlidePilot-macOS/issues/64) | Toolbar | Solved by the rewrite | Presenter window toolbar on Mac and iPad (ADR 0010) | – |
| [65](https://github.com/SlidePilot/SlidePilot-macOS/issues/65) | Timer colors at remaining-time thresholds | Request | 2.0 | [#166](https://github.com/SlidePilot/SlidePilot-Universal/issues/166) |
| [69](https://github.com/SlidePilot/SlidePilot-macOS/issues/69) | Zoom into slides | Request | 2.1 | [#172](https://github.com/SlidePilot/SlidePilot-Universal/issues/172) |
| [71](https://github.com/SlidePilot/SlidePilot-macOS/issues/71) | Upgrade to Sparkle 2 | Obsolete | No updater in the rewrite (DROP-02) | – |
| [74](https://github.com/SlidePilot/SlidePilot-macOS/issues/74) | Keyboard back to the slides after Return in the navigator | Request | 2.0; the rewrite still keeps the focus in the page field on the Mac | [#164](https://github.com/SlidePilot/SlidePilot-Universal/issues/164) |
| [75](https://github.com/SlidePilot/SlidePilot-macOS/issues/75) | Navigate by PDF outline | Request | 2.1 | [#170](https://github.com/SlidePilot/SlidePilot-Universal/issues/170) |
| [76](https://github.com/SlidePilot/SlidePilot-macOS/issues/76) | Resize the navigator | Solved by the rewrite | The navigator is a resizable sidebar (LAY-06) | – |
| [77](https://github.com/SlidePilot/SlidePilot-macOS/issues/77) | Timer controls by double click and right click | Solved by the rewrite | Timer toggle, Set Timer and Start/Stop in the toolbar (TIME-02 to TIME-04) | – |
| [78](https://github.com/SlidePilot/SlidePilot-macOS/issues/78) | Toolbar | Solved by the rewrite | Same as 64 | – |
| [80](https://github.com/SlidePilot/SlidePilot-macOS/issues/80) | Change slides with a mouse or trackpad swipe (Mac) | Request | 2.1 | [#174](https://github.com/SlidePilot/SlidePilot-Universal/issues/174) |
| [83](https://github.com/SlidePilot/SlidePilot-macOS/issues/83) | One note for all build steps of a frame | Request | 2.1 | [#168](https://github.com/SlidePilot/SlidePilot-Universal/issues/168) |
| [84](https://github.com/SlidePilot/SlidePilot-macOS/issues/84) | Video playback makes the window larger than the screen | Bug, avoided | The player is sized to the video's area on the slide (NAV-07); DEF-21 | – |
| [85](https://github.com/SlidePilot/SlidePilot-macOS/issues/85) | Slide overview as a grid | Request | 2.1 | [#171](https://github.com/SlidePilot/SlidePilot-Universal/issues/171) |
| [86](https://github.com/SlidePilot/SlidePilot-macOS/issues/86) | Break countdown for the audience | Request | 2.1 | [#173](https://github.com/SlidePilot/SlidePilot-Universal/issues/173) |
| [87](https://github.com/SlidePilot/SlidePilot-macOS/issues/87) | macOS Presenter Overlay | Obsolete | A system feature of screen sharing and video calls; the app needs nothing for it | – |

The old issues were not answered or closed; replies on the old repository are public and need the product owner's approval.
