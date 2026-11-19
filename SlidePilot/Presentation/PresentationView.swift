import SlidePilotCore
import SwiftUI

/// The registry of open documents, shared by all scenes (DOC-04).
typealias SessionRegistry = PresentationRegistry<PresentationSession>

/// What the audience sees: the current slide on black (DOC-04). Shown by the Mac
/// presentation window and the iPad external display. The drawing lies below the curtain;
/// the pointer (#29) follows above it, like in the old app.
struct PresentationView: View {
    let session: PresentationSession
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
            .drawingOverlay(session.drawing.drawings, page: session.currentPage)
            // Opaque, so it also hides the drawing (DRAW-09) and blocks clicks on the
            // slide's links while shown.
            CurtainCover(curtain: session.curtain)
        }
        .ignoresSafeArea()
        #if os(macOS)
        // A click makes the presentation window key; the keys keep working there (NAV-01).
        .slideNavigationKeys(session)
        .blackCurtainKey(session)
        #endif
    }
}
