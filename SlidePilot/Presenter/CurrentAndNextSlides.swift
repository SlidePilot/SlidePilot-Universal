import SlidePilotRendering
import SwiftUI

/// The current slide and the next-slide preview side by side, 60/40 like the old default
/// layout. Interim content of the document window until the presenter layout (#13, LAY-01).
struct CurrentAndNextSlides: View {
    let cache: RenderCache
    let page: Int

    /// The old app's default layout padding.
    private let padding: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let available = max(0, proxy.size.width - padding)
            HStack(spacing: padding) {
                SlideSurface(cache: cache, page: page, role: .current)
                    .frame(width: available * 0.6)
                NextSlidePreview(cache: cache, currentPage: page)
                    .frame(width: available * 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(padding)
    }
}
