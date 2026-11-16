# Prototype: drawing on iPad with PencilKit vs. a custom layer

Issue #11 · Parity DRAW-01, DRAW-02 (also DRAW-03, DRAW-04, DRAW-08, DRAW-10) · ADR 0010 · Phase 1 – Risk Prototypes

> **Status: done.** Simulator, unit-test, Apple Pencil (real iPads) and mouse/trackpad (Mac) results are in. The recommendation is approved by the product owner and recorded in [ADR 0016](../decisions/0016-drawing-engine.md).

## Question

The old app draws with a custom `NSView` (DRAW-01/02): one drawing per page, points stored relative to the page, a fixed 2 pt line, half-page sections when split notes are shown, and read-only copies on the presentation window, the next-slide preview and the thumbnails. ADR 0010 asks to evaluate PencilKit (`PKCanvasView` + `PKToolPicker`) on the iPad. The questions:

1. Can PencilKit keep the relative per-page model (DRAW-02), including half-page sections?
2. Can the presentation mirror the drawing read-only, live?
3. Can drawings be exported into the PDF (DRAW-10)?
4. Does the same model work with mouse and trackpad on the Mac?
5. Which UI (tool picker vs. own toolbar) fits parity and native design?

## What was tried

A probe app on the branch `proto/drawing` (draft PR #67, not merged). It shows an editable presenter surface, a read-only "presentation" mirror and a thumbnail, all of the same page section, and a log with timings and a Copy Log button.

- **Model (Core):** `PageDrawing` with `DrawingStroke`s of `RelativePoint`s (0…1, top-left origin of the displayed page), a stroke color and the canvas background. `CanvasMapping` maps between a canvas that shows a `PageSection` (full, left, right, top, bottom half) and relative page coordinates. Value types, `Sendable`, `Codable`.
- **Rendering:** `DrawingRenderer` draws a `PageDrawing` with Core Graphics (used for every read-only view and for the custom layer). `DrawingPDFExporter` writes one ink annotation per stroke into a copy of the PDF, handles `/Rotate`, and adds a white square annotation for the white canvas. `PencilKitBridge` converts `PKDrawing` ↔ model for a given mapping.
- **Engines (iPad):** a menu switches between
  - **Custom layer:** a SwiftUI `Canvas` with a `DragGesture` (mouse, trackpad, finger, Pencil).
  - **PencilKit:** `PKCanvasView` (transparent, monoline ink, width 2) with a `PKToolPicker` limited to one monoline item (`PKToolPicker(toolItems:)`, iOS 18+). The model stays the source of truth: the canvas is rebuilt from it when the page, section, size or undo state changes, and every finished stroke is converted back.
  - **Live mirror:** a passive `UIGestureRecognizer` on the canvas follows the touch from the first contact and feeds the stroke in progress to the read-only views. It never recognizes, so PencilKit's gestures are unaffected.
- **Mac:** only the custom layer; `PKCanvasView` and `PKToolPicker` do not exist on macOS. PencilKit's data types (`PKDrawing`, `PKStroke`) do, so the bridge and its tests run on the Mac.
- **Fixtures:** `notes-right.pdf` (split notes, the slide is the left half), `rotated.pdf`, `plain-slides.pdf`, bundled into the probe app.

**Environment:** Xcode with the iOS 27.2 / macOS 27.2 SDKs, deployment target 26.0. iPad simulators (iPad Pro 13-inch, iPad mini). Two real iPads (an iPad mini and an iPad with an A-series chip) with Apple Pencil, TestFlight builds of the probe. Unit tests on a Mac (Debug build, so timings are upper bounds).

## Measurements

| Measurement | Result |
|---|---|
| Model → `PKDrawing` → model, control points, all 5 sections, 1024 × 768 canvas | max. error 4 · 10⁻⁸ (relative), colors within 1/255 |
| Same stroke, presenter 640 × 480 → presentation 1920 × 1440 (left half) | lands on the same spot (< 0.01 pt) |
| Convert 200 strokes / 30,000 points: model → `PKDrawing` | 11.6 ms |
| Same, `PKDrawing` → model | 4.0 ms |
| Render 200 strokes / 30,000 points at 1920 × 1080 (Core Graphics) | 12.3 ms |
| Storage for those 200 strokes: JSON with `Double`s / `PKDrawing.dataRepresentation()` | 1.46 MB / 388 KB |
| One PencilKit stroke on the device: `PKDrawing` → model (interpolated, 2 pt spacing) | 0.2–2.8 ms for 250–2,400 points in the drawing |
| `canvasViewDrawingDidChange` calls while a stroke is drawn | **0** (only one call when the stroke ends) |
| Point size PencilKit stores for a monoline stroke of width 2 | **4 × 4 pt** |
| Custom layer on the device, one Pencil stroke | 50–190 points per 0.8–3.1 s (about 60 per second) |
| Export of 2–3 strokes on the device | 11–18 ms; ink annotation count matches the strokes |

## Device results (iPad with Apple Pencil)

| # | Check | Result |
|---|---|---|
| 1 | PencilKit: latency and live mirror | No noticeable latency. The mirror follows the stroke live and does not flash when the Pencil lifts |
| 2 | Tool picker color | Color in the picker and in the mirror match |
| 3 | "Pencil only" | With it on, the finger does not draw; the Pencil does |
| 4 | Mirror only at stroke end (live mirror off) | Works, but showing the stroke live is clearly preferred |
| 5 | Custom layer vs. PencilKit | Custom layer: fast circles look clearly angular, the line lags slightly. **PencilKit preferred** |
| 6 | Section change (left ↔ full), rotation, page change | Drawing stays on the same spot of the slide in both engines; PencilKit keeps the line width |
| 7 | Rotated PDF | Slide upright, strokes stay in place in both engines |
| 8 | Pages, undo/redo, clear, white canvas | Each page keeps its drawing; clear empties only the current page; the white canvas covers the slide and can be drawn on. Undo in the probe is one stack across pages (see below) |
| 9 | Export | Ink annotation count matches the number of strokes |
| 10 | Dark mode | With the canvas and picker forced to light, the picker offers black and black stays black. Without it, PencilKit shows black ink as white |
| 11 | Slow finger strokes | Shown in the mirror from the first touch, while drawing |
| 12 | Mac, mouse and trackpad (custom layer) | Drawing works |

## Observations

- **The relative model works with PencilKit.** Converting is exact and cheap, so PencilKit can be a pure input and display layer on top of the model. Rebuilding the `PKDrawing` on page, section or size changes is fast enough to do on every change.
- **Live mirroring needs a touch tracker.** `canvasViewDrawingDidChange` fires once per finished stroke. The old app updated the presentation while the mouse moved (`CanvasView.mouseDragged` → `drawingDidChange`). Following `drawingGestureRecognizer` works for the Pencil, but with a finger PencilKit starts that gesture only after a clear movement (to tell drawing from scrolling), so slow finger strokes did not show until they ended. A passive gesture recognizer that sees the touch from the first contact fixes this. A second finger cancels the stroke in progress, and fingers are ignored in "Pencil only" mode.
- **Keep the live stroke until the model has it.** Clearing the stroke in progress when the touch ends, before PencilKit reports the finished stroke, made the mirror flash empty for a moment.
- **PencilKit stores 4 pt points for width 2.** Rebuilding strokes with 2 pt points made them look thinner than when they were drawn. The production code uses the same point size PencilKit uses (measured, or derived from a drawn stroke). The size must live outside the canvas: rotating the iPad can recreate the canvas.
- **PencilKit adapts ink colors to dark mode.** In a dark UI the canvas shows black ink as white, and the tool picker offers white instead of black. Slides are light, so both the canvas (`overrideUserInterfaceStyle = .light`) and the tool picker (`colorUserInterfaceStyle = .light`) must be forced to light.
- **PencilKit smooths strokes.** It renders a spline through its control points; drawing the control points as a polyline (mirror, export) looks more angular. Sampling the rendered curve (`interpolatedPoints(by: .distance(2))`) fixes the look at about 10–20× more points, which matters for storage (see below).
- **The custom layer is not good enough for the Pencil.** A SwiftUI `DragGesture` delivers about 60 points per second and no coalesced or predicted touches, so fast curves become visibly angular and the line lags behind the Pencil tip.
- **The restricted tool picker works.** `PKToolPicker(toolItems:)` with one monoline item shows that pen, its colors (with a color well), undo/redo and a "…" menu. It does not show other tools, the eraser or the ruler. Its undo/redo act on PencilKit's own undo stack, not on the model; the production code has to route undo through the model (DRAW-08).
- **Undo should be per page.** The probe keeps one undo stack for all pages, so undo can remove a stroke on a page that is not visible. The production code keeps one undo history per page, so undo only ever changes the visible slide. Switching the canvas background is part of the history (DRAW-08), which matters because it clears the strokes (DRAW-04).
- **PDFKit annotations are main-thread objects.** Creating ink annotations off the main thread logs "dealloc from a background thread". Export runs on the main actor (or on a document copy owned by one task).
- **JSON with `Double` points is large** (1.46 MB for 30,000 points). The companion file (#25) should store points compactly (for example `Float32` pairs in a binary blob).
- **Simulator only:** after rotating, the PencilKit canvas in the simulator sometimes stopped showing strokes although the model and the mirror were correct. This did not happen on the devices.

## Limits

- **macOS:** no `PKCanvasView`, no `PKToolPicker`. Drawing on the Mac is always a custom layer.
- **iPadOS:** `PKCanvasView` gives Pencil-quality ink, palm rejection and a Pencil-only policy for free, but reports changes only per stroke and brings its own undo stack and color handling.
- **Both:** the model, the read-only rendering and the export are shared and independent of the input engine.

## Recommendation (approved, ADR 0016)

1. **One model in Core** (`PageDrawing`, relative points, per-page section mapping) as the single source of truth on both platforms. Read-only views (presentation, next-slide preview, thumbnails) and the PDF export render the model with Core Graphics; they never use PencilKit.
2. **Mac: custom drawing layer** (mouse and trackpad), as allowed by ADR 0010.
3. **iPad: `PKCanvasView` as the input layer**, with
   - the canvas and the tool picker forced to light colors,
   - monoline ink, width 2, strokes sampled along the rendered curve, rebuilt with PencilKit's own point size,
   - live mirroring through a passive touch tracker from the first contact,
   - one undo history per page through the model and the system `UndoManager`, not PencilKit's stack,
   - the drawing commands (colors, clear, canvas background, done) in our own toolbar and `Commands`, the same on both platforms. **No `PKToolPicker` for now** (product-owner decision): it adds little over parity (6 colors, no stroke eraser, DRAW-03), floats over the slide and brings its own colors and undo. Changing the color must stay quick: current color visible, presets one step away. The picker is revisited in 2.1. Apple Pencil double-tap and squeeze switch to the previously used color (DRAW-11).
4. **No custom layer on the iPad.** The device check showed it is clearly worse with the Pencil.

This is an architectural decision, so it becomes an ADR once approved.

## Follow-ups

- Issues for DRAW-01…10 (Phase 3): use the shared model and renderer; add the iPad input layer per the approved ADR; per-page undo (DRAW-08).
- #25 (companion file): store strokes compactly; drawings do not expire (ADR 0012).
- DRAW-10 export: run on the main actor; line width in page units (DEF-05).

## Re-running

Check out `proto/drawing`. Unit tests: `xcodebuild … -only-testing:SlidePilotRenderingTests/DrawingPrototypeTests test` prints lines starting with `PROBE`. App: run the scheme `SlidePilot` on an iPad (simulator or device) or on My Mac; use Copy Log to collect the results.
