---
title: Presenting
---

SlidePilot shows two things: the **presenter view** for you and the **presentation** for the audience, which shows only the current slide (with the pointer, drawings and curtain).

## On the Mac

The presenter view is the document window. The presentation is a second window that runs in full screen.

- **With a second screen** (a display, projector or AirPlay with "Use as Separate Display"), opening a PDF starts the presentation on that screen right away.
- **With one screen**, only the presenter window opens. Click **Start Presentation** in the toolbar or choose **Presentation ▸ Start Presentation** (⌥⌘P) to show the presentation in full screen in its own Space. Switch Spaces with Mission Control or a swipe.
- **Screens that come and go** are handled for you: connect a screen while presenting and the presentation moves there; disconnect it and the presentation moves to a remaining screen.
- Closing the presentation window keeps the presenter; **Start Presentation** opens it again. Closing the presenter window closes both.

Each open PDF has its own presenter and presentation window.

## On iPad and iPhone

Connect a display with a cable, or choose an AirPlay receiver (Apple TV, a smart TV or a Mac) in **Control Center ▸ Screen Mirroring**. SlidePilot then uses the display for the presentation, while your device keeps the presenter view.

- Without an open PDF, the display shows a "Ready to present" screen.
- With several SlidePilot windows on iPad, the display shows the PDF of the window you are working in.
- AirPlay shows the presentation only while SlidePilot is in the foreground; otherwise it mirrors your screen again.
- As long as no display is connected, the **Present on a second screen** button in the toolbar explains how to connect one.

Without SlidePilot Pro, the presentation on a second screen can be tried for 3 minutes at a time; see [SlidePilot Pro](/pro/).

## Changing slides

| Action | How |
|---|---|
| Next slide | → ↓ Page Down, a presentation clicker, or swipe left on the presenter view |
| Previous slide | ← ↑ Page Up, or swipe right |
| Previously viewed slide | **Go Back** in the toolbar or ⌃G; press it again to return |
| Any slide | The [slide navigator](/features/layout/#slide-navigator) |

Most presentation clickers send the arrow or Page keys, so they work without any setup. On iPad and iPhone, the keys work with a hardware keyboard, and a [remote device](/features/remote/) can change slides too.

## Links

Links in the PDF work on the current slide, the next-slide preview and the presentation:

- **Links to another slide** jump there; **Go Back** returns.
- **Web links** open in your browser.
- **Links to files** (`\href{run:…}` in LaTeX) open documents and videos in their app on the Mac and in Quick Look on iPad and iPhone. Programs and scripts are never opened. See [Beamer and LaTeX](/features/beamer/).

On iPad and iPhone, tap a link to follow it. A tap on a link waits a moment, in case you start the double tap that shows the [pointer](/features/pointer/).

## Keeping the display awake

Turn on **Settings ▸ General ▸ Keep display awake** so the display neither dims nor sleeps while SlidePilot is open. On iPad and iPhone this applies while SlidePilot is in the foreground.

## When the PDF changes

When the PDF changes on disk, for example because you recompiled it with LaTeX, SlidePilot reloads it at once and stays on the current slide. Notes, drawings and a playing video stay where they are.
