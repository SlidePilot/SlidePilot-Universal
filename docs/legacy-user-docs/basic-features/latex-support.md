# LaTeX Support

This page includes instructions for additional LaTex features that are supported by SlidePilot

## Embedded Video Playback

Videos can be embedded using Beamer's mutlimedia package. This can be done using the `\movie` tag in LaTeX. Options such as loop and autoplay are currently not supported. You can embed videos from your hard drive or from the web. Note that streaming (like a YouTube video) does not work.

**Hint:** If you are using notes using `pgfpages`, make sure to choose right or bottom for the notes position. Otherwise the `\movie` annotation is misplaced, due to a bug in `pgfpages`.

The following demo demonstrates how to embed a movie.

```
\documentclass{beamer}
\usepackage{multimedia}

\begin{document}
\frame{
    \frametitle{Embedded Video}  
    \begin{center}
        \movie{\includegraphics[width=\textwidth]{thumbnail.jpg}}{path/to/movie.mp4}
    \end{center}
}
\end{document}

```

## External Video Playback

Videos can be opened using QuickTime. See the following demo on how to embed a video for use with SlidePilot.

```
\documentclass{beamer}

\begin{document}
\frame{
    \frametitle{Video Slide} 
    \begin{center}
        \href{run:movie.MP4}{\includegraphics[width=\textwidth]{cover.PNG}}
    \end{center}
}
\end{document}
```

## Open Document

Open external documents by specifying a link in your presentation.

```
\documentclass{beamer}

\begin{document}
\frame{
    \frametitle{Document Slide} 
    \href{run:/path/to/my/document}{Link to an external document.}
}
\end{document}
```
