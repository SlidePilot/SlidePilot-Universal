import SlidePilotRendering
import SwiftUI

/// The current slide and the next-slide preview side by side, 60/40 like the old default
/// layout. Interim content of the document window until the presenter layout (#13, LAY-01).
struct CurrentAndNextSlides: View {
    let session: PresentationSession

    /// The old app's default layout padding.
    private let padding: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let available = max(0, proxy.size.width - padding)
            HStack(spacing: padding) {
                SlideSurface(cache: session.cache, page: session.currentPage, role: .current)
                    // VoiceOver users without a keyboard swipe up or down to change slides.
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: session.showNextPage()
                        case .decrement: session.showPreviousPage()
                        @unknown default: break
                        }
                    }
                    .frame(width: available * 0.6)
                NextSlidePreview(cache: session.cache, currentPage: session.currentPage)
                    .frame(width: available * 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(padding)
    }
}
