---
title: Notes
---

Show or hide the notes with **N** or the toolbar's **Layout** menu. SlidePilot has two notes modes, chosen in **Layout ▸ Notes Mode** (Mac: **View ▸ Notes Mode**):

- **Text**: notes you type, one page of notes per slide. Works with any PDF.
- **Split**: the notes are part of the PDF pages, as Beamer creates them with `show notes on second screen`. You see the notes half; the audience sees the slide half.

## Text notes

Click or tap into the notes and type. A slide without notes shows "Add notes for this slide".

- **Formatting**: bold, italic, underline, alignment, lists and spacing. On the Mac use the **Format** menu; on iPad and iPhone use the buttons above the keyboard.
- **Lists**: type `* ` or `- ` at the start of a line to start a bullet or dash list. Return continues the list; Return on an empty item ends it.
- **Text size**: **Format ▸ Font ▸ Bigger / Smaller** (⌘+ / ⌘-) changes the size for all slides of the PDF.
- **Done**: finish editing with **Done**, ⌘↩ or Esc, or by clicking outside the notes. While you edit, the arrow keys move in the text; change slides with ⌃⌘← and ⌃⌘→.

Notes are **saved automatically** with the PDF inside SlidePilot. There is nothing to save, and nothing changes in the PDF. See [Your Data](/your-data/).

## Split notes from Beamer

With `\setbeameroption{show notes on second screen=right}`, every PDF page holds the slide and its notes side by side. Choose where the notes are in **Split Position**:

| Split Position | Shortcut |
|---|---|
| None (no split) | ⌥⌘0 |
| Right | ⌥⌘1 |
| Left | ⌥⌘2 |
| Bottom | ⌥⌘3 |
| Top | ⌥⌘4 |

The audience, the next-slide preview, the navigator and remote devices then show only the slide half. The PDF can choose the position itself; see [Beamer and LaTeX](/features/beamer/#notes-on-the-second-screen).

## Importing and exporting notes

**Import Notes…** (⇧⌘O) and **Export Notes…** (⇧⌘E) read and write an RTF file with one section per slide. On the Mac they are in the **File** menu; on iPad and iPhone in the toolbar's **Import and Export** menu. Importing replaces the notes of every slide, after asking.

The RTF format is the one older SlidePilot versions used, so notes files from SlidePilot 1 can be imported. On the Mac, SlidePilot also finds such a file by itself when it sits next to the PDF and is named like `<pdf name>-notes.rtf` (also with `_` or a space, and `Notes` or `Notizen`): it asks once for access to the folder, then imports it.

In the RTF file each slide starts with a separator line; the number in it is ignored, the order counts:

```
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-1
Notes for the first slide
#SLIDEPILOT-NOTES-PAGE-SEPARATOR#-Page-2
Notes for the second slide
```

When you add or remove slides in the PDF, the notes stay with their slide number. Check the notes of the slides after the change.
