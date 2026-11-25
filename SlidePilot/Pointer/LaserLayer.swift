import SlidePilotCore
import SwiftUI

extension View {
    /// The laser pointer's strokes over a slide surface (PTR-08): the presenter's current
    /// slide and the presentation. Apply it to the `SlideSurface` itself, so the strokes
    /// are relative to the slide like the pointer. Part of the pointer overlay, one of the
    /// custom-drawn surfaces of ADR 0010.
    func laserOverlay(_ pointer: PointerState) -> some View {
        overlay { LaserLayer(pointer: pointer) }
    }
}

extension Date {
    /// The time base of `LaserTrail`, shared by the input and the `TimelineView`.
    var laserTime: TimeInterval { timeIntervalSinceReferenceDate }
}

/// Shows the strokes while they stay and fades them out after the last lift; with Reduce
/// Motion they vanish without animation. Never takes clicks or touches.
private struct LaserLayer: View {
    let pointer: PointerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The removal time of the strokes that are fading now; the timeline runs only then.
    @State private var fadingUntil: TimeInterval?

    var body: some View {
        let trail = pointer.laser
        if !trail.isEmpty {
            let isFading = fadingUntil != nil && fadingUntil == trail.removalTime
            ZStack {
                // With Reduce Motion the strokes vanish when the fade would start.
                if !(isFading && reduceMotion) {
                    TimelineView(.animation(paused: !isFading)) { timeline in
                        LaserCanvas(strokes: trail.strokes)
                            .opacity(isFading ? trail.opacity(at: timeline.date.laserTime, reduceMotion: false) : 1)
                    }
                }
            }
            .task(id: trail.removalTime) {
                guard let fadeStart = trail.fadeStart, let removalTime = trail.removalTime else { return }
                guard await sleep(until: fadeStart) else { return }
                fadingUntil = removalTime
                // A small margin, so the strokes are surely past their removal time.
                guard await sleep(until: removalTime + 0.05) else { return }
                // Not the clock's time: if the wall clock stepped back, the strokes would
                // otherwise never go. A new stroke changes the removal time and cancels this.
                pointer.removeExpiredLaser(at: max(Date.now.laserTime, removalTime))
            }
            .clipped()
            .allowsHitTesting(false)
            // The audience's strokes; VoiceOver users of the presenter gain nothing from them.
            .accessibilityHidden(true)
        }
    }

    /// Sleeps until `time`; false when cancelled.
    private func sleep(until time: TimeInterval) async -> Bool {
        let delay = time - Date.now.laserTime
        if delay > 0 {
            do { try await Task.sleep(for: .seconds(delay)) } catch { return false }
        }
        return !Task.isCancelled
    }
}

/// Draws the strokes in the laser's fixed red with a soft glow.
private struct LaserCanvas: View {
    let strokes: [[RelativePoint]]

    var body: some View {
        Canvas { context, size in
            let mapping = CanvasMapping(canvasWidth: size.width, canvasHeight: size.height)
            guard mapping.isValid else { return }
            var path = Path()
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                path.move(to: point(first, mapping))
                // A single point still shows as a dot through the round cap.
                for next in stroke.count == 1 ? [first] : Array(stroke.dropFirst()) {
                    path.addLine(to: point(next, mapping))
                }
            }
            let color = Color(cgColor: LaserTrail.color.cgColor)
            let style = StrokeStyle(lineWidth: LaserTrail.lineWidth, lineCap: .round, lineJoin: .round)
            context.addFilter(.shadow(color: color, radius: LaserTrail.glowRadius))
            context.stroke(path, with: .color(color), style: style)
        }
    }

    private func point(_ point: RelativePoint, _ mapping: CanvasMapping) -> CGPoint {
        let canvas = mapping.canvas(point)
        return CGPoint(x: canvas.x, y: canvas.y)
    }
}
