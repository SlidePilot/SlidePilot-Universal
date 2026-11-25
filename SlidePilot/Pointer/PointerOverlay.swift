import SlidePilotCore
import SwiftUI

extension PresentationSession {
    /// The pointer of the chosen appearance (PTR-02). Individual is the custom pointer of
    /// the pointer editor (PTR-04), one for all documents (PTR-05).
    func pointerConfiguration(settings: AppSettings?) -> PointerConfiguration {
        pointer.appearance.configuration(individual: settings?.individualPointer ?? .defaultIndividual)
    }

    /// Where the audience sees the pointer: the presenter's or the remote's (PTR-01, REM-05).
    var visiblePointerLocation: CGPoint? {
        pointer.visibleLocation(remote: remotePointerLocation)
    }
}

/// The pointer on the presentation (PTR-01). It fills the presentation and puts the
/// pointer's hot spot on `slideFrame`, given in this view's coordinates.
struct PresentationPointerLayer: View {
    let session: PresentationSession
    let slideFrame: CGRect
    @Environment(AppSettings.self) private var settings: AppSettings?

    var body: some View {
        PointerMark(
            location: session.visiblePointerLocation,
            configuration: session.pointerConfiguration(settings: settings),
            slideFrame: slideFrame
        )
            // The audience's pointer; VoiceOver users of the presenter gain nothing from it.
            .accessibilityHidden(true)
    }
}

/// Draws the pointer with its hot spot at `location` (relative to `slideFrame`).
private struct PointerMark: View {
    let location: CGPoint?
    let configuration: PointerConfiguration
    let slideFrame: CGRect

    var body: some View {
        ZStack {
            if let location, slideFrame.width > 0, slideFrame.height > 0 {
                let hotSpot = PointerImage.hotSpot(of: configuration)
                // A point-sized anchor at the location; the pointer hangs from it by its hot spot.
                Color.clear
                    .frame(width: 0, height: 0)
                    .overlay(alignment: .topLeading) {
                        PointerImage(configuration: configuration)
                            .alignmentGuide(.leading) { $0.width * hotSpot.x }
                            .alignmentGuide(.top) { $0.height * hotSpot.y }
                    }
                    .position(
                        x: slideFrame.minX + location.x * slideFrame.width,
                        y: slideFrame.minY + location.y * slideFrame.height
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Moves the pointer with the mouse, trackpad or Apple Pencil hovering over the
    /// presenter's current slide and, on iPad, with a double tap and hold (PTR-01). With
    /// the laser pointer, dragging draws strokes that fade out (PTR-08).
    /// Apply it to the `SlideSurface` itself, so the location is relative to the slide.
    func presenterPointer(_ session: PresentationSession) -> some View {
        modifier(PresenterPointer(session: session))
    }

    /// Over the presentation the mouse pointer looks like the pointer (PTR-06).
    func presentationPointerStyle(_ session: PresentationSession) -> some View {
        #if os(macOS)
        modifier(PresentationPointerStyle(session: session))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct PresentationPointerStyle: ViewModifier {
    let session: PresentationSession
    @Environment(AppSettings.self) private var settings: AppSettings?

    func body(content: Content) -> some View {
        content
            .pointerStyle(session.pointer.isShown ? PointerCursor.style(for: session.pointerConfiguration(settings: settings)) : nil)
    }
}
#endif

private struct PresenterPointer: ViewModifier {
    let session: PresentationSession
    @Environment(AppSettings.self) private var settings: AppSettings?
    @State private var size = CGSize.zero
    /// Resets when a drag ends or is cancelled, which ends the laser stroke.
    @GestureState private var isLaserDragging = false
    #if os(iOS)
    @State private var linkTaps = LinkTapDelay()
    private let tip = TouchPointerTip()
    #endif

    private var pointer: PointerState { session.pointer }
    private var isDrawing: Bool { session.drawing.isActive }
    /// Draw mode keeps the mouse and fingers for the drawing.
    private var drawsLaser: Bool { pointer.isLaserActive && !isDrawing }

    /// A laser stroke: begins where the drag started, then follows it.
    private var laserDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($isLaserDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                pointer.laserDragged(from: value.startLocation, to: value.location, inSlideOfSize: size, time: Date.now.laserTime)
                // The dot rides on the stroke's tip.
                pointer.presenterMoved(to: value.location, inSlideOfSize: size)
            }
    }

    func body(content: Content) -> some View {
        let configuration = session.pointerConfiguration(settings: settings)
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .laserOverlay(pointer)
            .onChange(of: isLaserDragging) { _, isDragging in
                guard !isDragging else { return }
                pointer.laserEnded(time: Date.now.laserTime)
                #if os(iOS)
                // A lifted finger no longer points; a hovering Pencil sets the dot again.
                pointer.presenterEnded()
                #endif
            }
            // Draw mode or a layout change can remove the slide mid-drag; the gesture
            // then never ends, so end the stroke here.
            .onDisappear { pointer.laserEnded(time: Date.now.laserTime) }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer.presenterMoved(to: location, inSlideOfSize: size)
                case .ended: pointer.presenterEnded()
                }
            }
            #if os(iOS)
            // With the laser, a finger or Pencil drag on the current slide draws (PTR-08);
            // swipes on the rest of the presenter still change slides.
            .gesture(laserDrag, isEnabled: drawsLaser)
            // Double tap and hold points, whether or not the pointer is shown; a one-finger
            // swipe always changes slides. Off in draw mode, where a finger draws, and while
            // the laser draws.
            .gesture(
                TouchPointerGesture(
                    isEnabled: !isDrawing && !drawsLaser,
                    began: {
                        linkTaps.pointingBegan()
                        tip.invalidate(reason: .actionPerformed)
                    },
                    moved: { pointer.touchMoved(to: $0, inSlideOfSize: size) },
                    ended: {
                        linkTaps.pointingEnded()
                        pointer.touchEnded()
                    }
                )
            )
            .environment(\.linkTapDelay, linkTaps)
            // A link tapped on the previous slide or before drawing must not follow later.
            .onChange(of: session.currentPage) { linkTaps.cancel() }
            .onChange(of: isDrawing) { linkTaps.cancel() }
            .onDisappear {
                linkTaps.cancel()
                pointer.touchEnded()
            }
            // iPad has no cursor image to swap (PTR-06), so the presenter sees the pointer
            // drawn under the finger, Pencil or trackpad pointer.
            .overlay {
                PointerMark(
                    location: pointer.visibleLocation(remote: nil),
                    configuration: configuration,
                    slideFrame: CGRect(origin: .zero, size: size)
                )
                .accessibilityHidden(true)
            }
            #else
            // Hover stops while a mouse button is held; the old app kept following then too.
            // Simultaneous, so clicks still reach links and videos.
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { pointer.presenterMoved(to: $0.location, inSlideOfSize: size) },
                isEnabled: pointer.isShown && !drawsLaser
            )
            // With the laser, press and drag draws (PTR-08); also simultaneous, for links.
            .simultaneousGesture(laserDrag, isEnabled: drawsLaser)
            // Like the old app, the mouse pointer over the current slide looks like the
            // pointer the audience sees; in draw mode the canvas keeps its own.
            .pointerStyle(pointer.isShown && !isDrawing ? PointerCursor.style(for: configuration) : nil)
            #endif
    }
}
