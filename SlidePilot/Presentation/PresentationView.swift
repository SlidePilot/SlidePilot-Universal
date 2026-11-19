import SlidePilotCore
import SwiftUI

/// The registry of open documents, shared by all scenes (DOC-04).
typealias SessionRegistry = PresentationRegistry<PresentationSession>

/// What the audience sees: the current slide on black (DOC-04). Shown by the Mac
/// presentation window and the iPad external display. Later issues add the drawing below
/// the curtain and the pointer above it, like in the old app.
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
            // Opaque, so it also blocks clicks on the slide's links while shown.
            CurtainCover(curtain: session.curtain)
        }
        .ignoresSafeArea()
        // The same players as the presenter, so the videos play mirrored (NAV-07).
        .environment(session.linkedFiles)
        #if os(macOS)
        // A click makes the presentation window key; the keys keep working there (NAV-01).
        .slideNavigationKeys(session)
        .blackCurtainKey(session)
        #endif
    }
}
