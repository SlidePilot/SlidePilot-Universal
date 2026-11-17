import SlidePilotCore
import SwiftUI

/// The registry of open documents, shared by all scenes (DOC-04).
typealias SessionRegistry = PresentationRegistry<PresentationSession>

/// What the audience sees: the current slide on black (DOC-04). Shown by the Mac
/// presentation window and the iPad external display. Later issues add the pointer,
/// curtain and drawing on top.
struct PresentationView: View {
    let session: PresentationSession

    var body: some View {
        ZStack {
            Color.black
            SlideSurface(cache: session.cache, page: session.currentPage, role: .presentation)
        }
        .ignoresSafeArea()
    }
}
