---
title: Beamer and LaTeX
nav_order: 9
parent: Features
---

# Beamer and LaTeX

SlidePilot understands a few things that LaTeX Beamer puts into a PDF. Recompile while the PDF is open: SlidePilot reloads it and stays on the current slide.

## Notes on the second screen

Beamer can put notes next to each slide:

```latex
\documentclass{beamer}
\usepackage{pgfpages}
\setbeameroption{show notes on second screen=right}

\begin{document}
\begin{frame}{Kepler's laws}
  Planets move on ellipses.
  \note{Mention Tycho Brahe's observations.}
\end{frame}
\end{document}
```

Open the PDF and choose **Split Position ▸ Right** (see [Notes](notes.md#split-notes-from-beamer)), or let the PDF choose it: add one of the keywords `SP-Right`, `SP-Left`, `SP-Top` or `SP-Bottom` (exactly like this) to the PDF, and SlidePilot opens it in Split mode at that position:

```latex
\hypersetup{pdfkeywords={SP-Right}}
```

A position you choose yourself wins over the keyword.

**Tip:** use `right` or `top` for the notes. With `left` or `bottom`, pgfpages leaves links and videos at their position on the plain slide, which is then in the notes half.

## Videos

Embed videos with the `multimedia` package. The picture in the first argument is shown until the video plays:

```latex
\usepackage{multimedia}
...
\movie[autostart,loop]{\includegraphics[width=\textwidth]{poster.png}}{videos/demo.mp4}
```

Click or tap the video to play it. The presentation shows it at the same time, and the sound plays once. These options work:

| Option | Effect |
|---|---|
| `autostart` | Plays as soon as the slide is shown |
| `loop`, `repeat` | Plays again and again (also `palindrome`, which plays as a loop) |
| `start=5s` | Starts at that time |
| `duration=10s` | Stops after that time |

- A video that appears on several overlay steps of one frame at the same place keeps playing across them.
- The next-slide preview shows only the picture.
- Paths are relative to the PDF. The first time, SlidePilot asks for access to the folder of the PDF so it can read the video (**Allow Access…**).
- Videos stored inside the PDF play without folder access.
- Web addresses work for video files, but not streaming sites like YouTube. `showcontrols` is not supported.

## Links to files

`\href{run:…}` opens a file next to the PDF, for example a video in its own player or another document:

```latex
\href{run:videos/demo.mp4}{\includegraphics[width=\textwidth]{poster.png}}
\href{run:handout.pdf}{The handout}
```

On the Mac the file opens in its app; on iPad and iPhone it opens in Quick Look. For security, SlidePilot opens documents and media only, never programs or scripts. Like videos, these files need access to the PDF's folder.

## Other links

`\hyperlink`, `\href{https://…}` and the Beamer navigation symbols that point to a slide work as described in [Presenting](presenting.md#links).
