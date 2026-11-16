# 0016 – Drawing: shared relative model, PencilKit input on iPad, own toolbar

- Status: Accepted
- Date: 2026-11-16

## Context
The old app draws with a custom `NSView` (DRAW-01/02): one drawing per page, points relative to the page, a fixed 2 pt line, half-page sections when split notes are shown, and read-only copies on the presentation window, the next-slide preview and the thumbnails. ADR 0010 asks to evaluate PencilKit and its tool picker on the iPad.

The Phase 1 prototype (#11, [findings](../prototypes/drawing.md)) compared a custom SwiftUI layer with `PKCanvasView` on real iPads with Apple Pencil, and the custom layer on the Mac:
- The relative model converts to and from `PKDrawing` exactly and cheaply, for every page section.
- With the Pencil, the custom layer draws visibly angular curves and lags slightly; PencilKit does not.
- PencilKit reports a stroke only when it ends. A passive touch tracker mirrors strokes live from the first contact, also slow finger strokes.
- PencilKit adapts ink to dark mode and stores 4 pt points for a width-2 monoline stroke; both need handling.
- `PKToolPicker` can be restricted to one monoline pen, but it brings its own colors and undo stack, floats over the slide and has no commands for clearing the page, the canvas background or leaving draw mode.

## Decision
**Model and rendering (both platforms)**
- One drawing model in `SlidePilotCore` is the single source of truth: per page, strokes of points relative to the displayed page (0…1), a stroke color and the canvas background (transparent or white). Half-page sections are a mapping between a canvas and the page, not separate drawings.
- Read-only views (presentation, next-slide preview, thumbnails) and the PDF export (DRAW-10) render the model with Core Graphics. They never use PencilKit.

**Input**
- **iPad (and iPhone, ADR 0015):** `PKCanvasView` is the input layer on top of the model, with monoline ink at width 2, the canvas forced to light colors, strokes sampled along PencilKit's rendered curve, and strokes rebuilt from the model with PencilKit's own point size. A passive touch tracker feeds the stroke in progress to the read-only views from the first contact; a second finger cancels it.
- **Mac:** a custom drawing layer for mouse and trackpad (allowed by ADR 0010).
- No custom drawing layer on the iPad.

**Controls**
- **No `PKToolPicker` for now.** Drawing is controlled by our own toolbar and `Commands`, the same on Mac and iPad: the six preset colors of the old app, clear, transparent or white canvas, done (DRAW-03, DRAW-04). Only standard components are used (ADR 0010).
- **Changing the color must be quick:** the toolbar shows the current color, and the six presets are reachable in one step from the toolbar, without opening a settings sheet or a nested menu.
- Whether the iPad shows the tool picker (and more pens) is revisited after 2.0, as a new decision.

**Undo**
- One undo history per page, through the model and the system `UndoManager` (DRAW-08). Undo only changes the visible slide. Clearing and changing the canvas background are part of the history.

## Consequences
- Pencil-quality ink, palm rejection and a Pencil-only policy come from PencilKit on the iPad; the Mac keeps its own layer, so the input code differs per platform while model, rendering and export are shared.
- Without the tool picker there are no extra pens, no stroke eraser, no ruler and no Pencil Pro squeeze palette; the scope stays at parity (DRAW-03). Adding the picker later needs undo routed through the model and a decision on how its colors map to the presets.
- PencilKit's own undo stack is not used; the canvas is rebuilt from the model after undo and redo.
- Strokes are stored compactly in the companion file (#25), not as JSON `Double`s.
- Parity items DRAW-01 and DRAW-03 note the decision; their status stays `planned` until implemented in Phase 3.
