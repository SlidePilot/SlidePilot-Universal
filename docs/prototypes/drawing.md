# Prototype: drawing on iPad with PencilKit vs. a custom layer

Issue #11 · Parity DRAW-01, DRAW-02 (also DRAW-03, DRAW-04, DRAW-08, DRAW-10) · ADR 0010 · Phase 1 – Risk Prototypes

> **Status: draft.** Simulator and unit-test results are in. The Apple Pencil checks on a real iPad and the mouse/trackpad check on the Mac are still open (see [Open device checks](#open-device-checks)). The recommendation needs the product owner's approval and then an ADR.

## Question

The old app draws with a custom `NSView` (DRAW-01/02): one drawing per page, points stored relative to the page, a fixed 2 pt line, half-page sections when split notes are shown, and read-only copies on the presentation window, the next-slide preview and the thumbnails. ADR 0010 asks to evaluate PencilKit (`PKCanvasView` + `PKToolPicker`) on the iPad. The questions:

1. Can PencilKit keep the relative per-page model (DRAW-02), including half-page sections?
2. Can the presentation mirror the drawing read-only, live?
3. Can drawings be exported into the PDF (DRAW-10)?
4. Does the same model work with mouse and trackpad on the Mac?
5. Which UI (tool picker vs. own toolbar) fits parity and native design?

## What was tried

A probe app on the branch `proto/drawing` (draft PR, not merged). It shows an editable presenter surface, a larger read-only "presentation" mirror and a thumbnail, all of the same page section, and a log with timings.

- **Model (Core):** `PageDrawing` with `DrawingStroke`s of `RelativePoint`s (0…1, top-left origin of the displayed page), a stroke color and the canvas background. `CanvasMapping` maps between a canvas that shows a `PageSection` (full, left, right, top, bottom half) and relative page coordinates. Value types, `Sendable`, `Codable`.
- **Rendering:** `DrawingRenderer` draws a `PageDrawing` with Core Graphics (used for every read-only view and for the custom layer). `DrawingPDFExporter` writes one ink annotation per stroke into a copy of the PDF, handles `/Rotate`, and adds a white square annotation for the white canvas. `PencilKitBridge` converts `PKDrawing` ↔ model for a given mapping.
- **Engines (iPad):** a segmented control switches between
  - **Custom layer:** a SwiftUI `Canvas` with a `DragGesture` (mouse, trackpad, finger, Pencil).
  - **PencilKit:** `PKCanvasView` (transparent, monoline ink, 2 pt) with a `PKToolPicker` limited to one monoline item (`PKToolPicker(toolItems:)`, iOS 18+). The model stays the source of truth: the canvas is rebuilt from it when the page, section, size or undo state changes, and every finished stroke is converted back.
- **Mac:** only the custom layer; `PKCanvasView` and `PKToolPicker` do not exist on macOS. PencilKit's data types (`PKDrawing`, `PKStroke`) do, so the bridge and its tests run on the Mac.
- **Fixtures:** `notes-right.pdf` (split notes, the slide is the left half), `rotated.pdf`, `plain-slides.pdf`, bundled into the probe app.

**Environment:** Xcode with the iOS 27.2 / macOS 27.2 SDKs, deployment target 26.0. iPad Pro 13-inch (M5) simulator (touches injected, no Pencil hardware). Unit tests on a Mac (Debug build, so timings are upper bounds).

## Measurements

| Measurement | Result |
|---|---|
| Model → `PKDrawing` → model, control points, all 5 sections, 1024 × 768 canvas | max. error 4 · 10⁻⁸ (relative), colors within 1/255 |
| Same stroke, presenter 640 × 480 → presentation 1920 × 1440 (left half) | lands on the same spot (< 0.01 pt) |
| Convert 200 strokes / 30,000 points: model → `PKDrawing` | 11.6 ms |
| Same, `PKDrawing` → model | 4.0 ms |
| Render 200 strokes / 30,000 points at 1920 × 1080 (Core Graphics) | 12.3 ms |
| Storage for those 200 strokes: JSON with `Double`s / `PKDrawing.dataRepresentation()` | 1.46 MB / 388 KB |
| One PencilKit stroke in the app: `PKDrawing` → model | 0.05–0.12 ms |
| `canvasViewDrawingDidChange` calls while a stroke is drawn | **0** (only one call when the stroke ends) |
| Interpolated sampling (2 pt spacing) of a 20-control-point stroke | 415 points |
| Export: ink annotation position for `/Rotate` 0 and 90, line width, white canvas | correct (unit tests) |

## Observations

- **The relative model works with PencilKit.** Converting is exact and cheap, so PencilKit can be a pure input and display layer on top of the model. Rebuilding the `PKDrawing` on page, section or size changes is fast enough to do on every change.
- **No live mirroring from PencilKit's delegate.** `canvasViewDrawingDidChange` fires once per finished stroke. The old app updated the presentation while the mouse moved (`CanvasView.mouseDragged` → `drawingDidChange`). Following `PKCanvasView.drawingGestureRecognizer` with an extra target gives the touch locations during the stroke; the probe uses that to mirror live (option "Mirror PencilKit strokes live"). **Needs a device check** (Pencil, latency).
- **PencilKit adapts ink colors to dark mode.** In a dark UI the canvas showed a lighter blue than the model color, and the tool picker offers white first. Slides are light, so the canvas must use `overrideUserInterfaceStyle = .light`.
- **PencilKit smooths strokes.** It renders a spline through its control points; drawing the control points as a polyline (mirror, export) looks more angular. Sampling the rendered curve (`interpolatedPoints(by: .distance(2))`) fixes the look at about 10–20× more points, which matters for storage (see below).
- **Line width differs between engines.** The old app's 2 pt is in view points, so it looks thinner on a larger presentation window. PencilKit's monoline at width 2 looked slightly heavier than the Core Graphics 2 pt line. Export uses 2 pt in page units (DEF-05).
- **The restricted tool picker works.** `PKToolPicker(toolItems:)` with one monoline item shows that pen, its colors (with a color well), undo/redo and a "…" menu. It does not show other tools, the eraser or the ruler. Its undo/redo act on PencilKit's own undo stack, not on the model; the production code has to route undo through the model (DRAW-08).
- **SwiftUI `DragGesture` drops points.** In the simulator the custom layer received 5 of 11 injected points and draws straight segments. A `DragGesture` does not deliver coalesced or predicted touches. For Pencil quality a custom layer on iPad would need a UIKit touch handler with `coalescedTouches`/`predictedTouches`. **Needs a device check.**
- **PDFKit annotations are main-thread objects.** Creating ink annotations off the main thread logs "dealloc from a background thread". Export runs on the main actor (or on a document copy owned by one task).
- **JSON with `Double` points is large** (1.46 MB for 30,000 points). The companion file (#25) should store points compactly (for example `Float32` pairs in a binary blob).

## Limits

- **macOS:** no `PKCanvasView`, no `PKToolPicker`. Drawing on the Mac is always a custom layer.
- **iPadOS:** `PKCanvasView` gives Pencil-quality ink, palm rejection and a Pencil-only policy for free, but reports changes only per stroke and brings its own undo stack and color handling.
- **Both:** the model, the read-only rendering and the export are shared and independent of the input engine.

## Recommendation (proposal, not yet approved)

1. **One model in Core** (`PageDrawing`, relative points, per-page section mapping) as the single source of truth on both platforms. Read-only views (presentation, next-slide preview, thumbnails) and the PDF export render the model with Core Graphics; they never use PencilKit.
2. **Mac: custom drawing layer** (mouse and trackpad), as allowed by ADR 0010.
3. **iPad: `PKCanvasView` as the input layer**, with
   - `overrideUserInterfaceStyle = .light`,
   - monoline ink, 2 pt, strokes sampled along the rendered curve,
   - live mirroring through `drawingGestureRecognizer` (if the device check confirms it),
   - undo/redo through the model and the system `UndoManager`, not PencilKit's stack,
   - the drawing commands (colors, clear, canvas background, done) in our own toolbar and `Commands`, the same on both platforms. Whether `PKToolPicker` is shown in addition (only the monoline pen) is a design decision for the product owner; the parity scope (6 colors, no stroke eraser, DRAW-03) argues against more tools.
4. If the device checks show that live mirroring through the gesture recognizer is not reliable, fall back to the custom layer on iPad as well, with a UIKit touch handler that uses coalesced and predicted touches.

This is an architectural decision, so it becomes an ADR once approved.

## Open device checks

On an iPad with Apple Pencil (TestFlight or cable build of `proto/drawing`):

1. PencilKit engine: draw with the Pencil. Is the latency like Notes? Does the presentation mirror follow the stroke live?
2. Same with "Pencil only" on: does the finger stay inactive (and could scroll or navigate instead)?
3. Custom layer engine: draw with the Pencil. Do fast strokes look angular compared with PencilKit?
4. Switch the section (left ↔ full) and rotate the iPad: does the drawing stay on the same spot of the slide?
5. Export: open the exported PDF (from the app's temporary folder, via the log) in Preview or Files.

On the Mac (run `proto/drawing`, My Mac): draw with mouse and trackpad on the custom layer, check that the mirror follows live and that undo, clear and white canvas work.

## Follow-ups

- Issues for DRAW-01…10 (Phase 3): use the shared model and renderer; add the iPad input layer per the approved ADR.
- #25 (companion file): store strokes compactly; drawings do not expire (ADR 0012).
- DRAW-10 export: run on the main actor; line width in page units (DEF-05).

## Re-running

Check out `proto/drawing`. Unit tests: `xcodebuild … -only-testing:SlidePilotRenderingTests/DrawingPrototypeTests test` prints lines starting with `PROBE`. App: run the scheme `SlidePilot` on an iPad (simulator or device) or on My Mac.
