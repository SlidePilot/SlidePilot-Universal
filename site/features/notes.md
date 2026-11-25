---
title: Notes
nav_order: 4
parent: Features
---

# Notes

SlidePilot allows you to view notes with your presentation. There are two possible modes:

* [Text Mode](notes.md#text-mode): In this mode you can add notes to any PDF and save them to an `.rtf` file.
* [Split Mode](notes.md#split-mode): This mode is intended for PDF created with LaTex Beamer, which have a second notes slide displayed next to the actual slide.

## Text Mode

You can add notes to any PDF using the notes text mode. Start by showing the notes view by pressing the  **N** key or select *Notes* → *Show Notes*. Next select *Notes* → *Notes Mode* → *Text* if not already selected. You should now see the notes editor on the left side.

Enter your notes in the editor as you want. You can format the text using the options in the *Format* menu.

### Opening and Saving

Save your notes by pressing **⌘ + S** or select *Notes* → *Save Notes*. SlidePilot will propose you a file name for saving the notes document. It is recommended to choose this filename, because then SlidePilot will automatically open this notes file the next time you open the current PDF.

Open a notes file by pressing **⌘ + ⇧ + O** or select *Notes* → *Open Notes*. This way you can open any other `.rtf` file (see [File Format](notes.md#file-format) section for more details on the `.rtf` files).

Create a new notes file by pressing **⌘ + N** or select *Notes* → *New Notes*

{% hint style="info" %}
*When your notes file has a filename like* `<pdf-name>-notes.rtf`*, SlidePilot will automatically open this notes file with your PDF named* `<pdf-name>.pdf`*.*

*Notes files with the filename like* `<pdf-name>-( |_|-)(notes|Notes|Notizen)` *are also recognized by SlidePilot.*
{% endhint %}

### Editing and Styling

You can format your notes by going to the *Format* menu and select a style option. Depending on the style option you chose, the style is applied to the current selection or the current line.

However changing the font size is applied to all your notes on all pages.

When you are in the notes editor (i.e. the notes editor is highlighted), you can exit editing by either pressing the Finish button, pressing **⌘ + ↩** or by clicking anywhere outside of the editor.

To change slides while editing use the key combinations **⌘ + ctrl + ←**  and **⌘ + ctrl + →**.

### File Format

The notes for a PDF are saved in a single `.rtf` file. You can edit the file using any text editor that support `.rtf` files and then open the file again in SlidePilot.

It is however important that you keep the file structure. For each page in the PDF, the `.rtf` file contains a specific separator (`#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-X`), followed by the notes itself for the corresponding page. Example file contents:

```
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-1
Notes Content for first page ...
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-2
And for second page ...
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-3
And so on
```

SlidePilot parses the notes files using the separator. But SlidePilot doesn't pay respect to the page numbers, these are just for you to better orient yourself in the file (to be more precise, SlidePilot searches for separators that match the regular expression pattern `#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-[0-9]*` )

In the case you update you presentation PDF and possibly add a page, your notes may be on the wrong page. In this case you can edit the notes file manually to insert a blank notes page. Say we have a PDF with three pages, the notes file as in the above example and add a new page after page two. Then add a new separator (as said before, the number doesn't matter and will be adjusted automatically the next time you save the notes using SlidePilot) after the notes of page two **and** add a blank line. See the following example:

```
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-1
Notes Content for first page ...
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-2
And for second page ...
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-2

#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-3
And so on
```

## Split Mode

If your PDF is constructed of slides, which are split in half, one half for presentation and one half for notes, SlidePilot allows you display the slide halves separatly.

This is the case for note slides created with LaTex Beamer.&#x20;

Use the following code to setup your .tex file for presenting notes on a second screen.

```
\documentclass{beamer}
\usepackage{pgfpages}

\setbeameroption{show notes on second screen}
```

If you have a PDF, which uses Beamer notes on the second screen, you can split the PDF by going in the menu and selecting *Notes* → *Notes Mode* → *Split*. Then you can go to *Notes* → *Split Position* and choose the position, where your notes are in the PDF. If you now also want to display the notes slide in the Presenter Window, press the **N** key or select *Notes* → *Show Notes*.

### Example

Full example of a .tex file using Beamer notes.

```
\documentclass{beamer}
\usepackage{pgfpages}

\setbeameroption{show notes on second screen}

\begin{document}
\frame{
    \frametitle{Demo Slide} 
    Content of the demo slide.
}
\note{
    \begin{itemize}
        \item These are some
        \item items in a list
        \item full of notes
    \end{itemize}
}
\end{document}
```

### Automatically detect Notes Position

SlidePilot is able to automatically detect the notes position of your PDF if you add a special keyword to it. These are:

* **SP-Right** to specify notes position right
* **SP-Left** to specify notes position left
* **SP-Top** to specify notes position top
* **SP-Bottom** to specify notes position bottom

Add those metatags to the preamble of your LaTeX using either of the following commands:

```
\pdfinfo{/Keywords (SP-Right)}

% or

\hypersetup{
	pdfkeywords={SP-Right}
}
```

When first opening the document with SlidePilot and one of these tags are detected, then SlidePilot will automatically choose the correct notes position. If you've already opened this document in SlidePilot but you've chosen a different notes position, this notes position will then be used when opening a document instead of the detected notes position (see [Saving Layout Configurations](slide-overview.md#saving-layout-configurations)).
