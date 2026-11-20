import SlidePilotCore
import SwiftUI

/// The registry of open documents, shared by all scenes (DOC-04).
typealias SessionRegistry = PresentationRegistry<PresentationSession>

/// What the audience sees: the current slide on black (DOC-04). Shown by the Mac
/// presentation window and the iPad external display. The drawing lies below the curtain;
/// the pointer stays above it, like in the old app (PTR-01).
struct PresentationView: View {
    let session: PresentationSession
    /// Where the slide is, for the pointer above the curtain.
    @State private var slideFrame = CGRect.zero
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black
            SlideSurface(
                cache: session.cache,
                page: session.currentPage,
                role: .presentation,
                pageLinkAction: session.showPage,
                crossfades: SlideCrossfade.isActive(setting: settings.crossfadesSlides, reduceMotion: reduceMotion)
            )
            // Read-only and live while it is drawn (DRAW-01).
            .drawingOverlay(session.drawing.drawings, page: session.currentPage, isOutlined: false)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { slideFrame = $0 }
            // Opaque, so it also hides the drawing (DRAW-09) and blocks clicks on the
            // slide's links while shown.
            CurtainCover(curtain: session.curtain)
            PresentationPointerLayer(session: session, slideFrame: slideFrame)
        }
        .coordinateSpace(.named(Self.space))
        .ignoresSafeArea()
        .presentationPointerStyle(session)
        // The same players as the presenter, so the videos play mirrored (NAV-07).
        .environment(session.linkedFiles)
        #if os(macOS)
        // A click makes the presentation window key; the keys keep working there (NAV-01).
        .slideNavigationKeys(session)
        .blackCurtainKey(session)
        #endif
    }

    private nonisolated static let space = "presentation"
}
