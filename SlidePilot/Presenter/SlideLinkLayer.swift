import SlidePilotRendering
import SwiftUI

/// Invisible hit areas over the links of a slide (NAV-05).
///
/// Part of the slide surface (ADR 0010): links are drawn by the PDF itself, so there is no
/// system control to use. Each area shows the system's link pointer and follows the link on
/// a click or tap. Later areas are on top, matching the PDF's drawing order.
struct SlideLinkLayer: View {
    let links: [SlideLink]
    let region: PageRegion
    let follow: (SlideLink) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                if let rect = link.unitRect(in: region) {
                    // A tap gesture, not a button: buttons would take the keyboard focus
                    // from the slide navigation keys.
                    Color.clear
                        .contentShape(.rect)
                        .frame(width: rect.width * size.width, height: rect.height * size.height)
                        .linkPointer()
                        .onTapGesture { follow(link) }
                        .position(x: rect.midX * size.width, y: rect.midY * size.height)
                }
            }
        }
    }
}

extension SlideLink {
    /// The VoiceOver action that follows this link.
    var accessibilityActionName: Text {
        switch target {
        case .page(let index): Text("Go to slide \(index + 1)")
        case .url(let url): Text("Open link \(url.absoluteString)")
        }
    }
}

private extension View {
    /// The pointing hand on Mac; on iPad the pointer snaps to the link area.
    @ViewBuilder
    func linkPointer() -> some View {
        #if os(macOS)
        pointerStyle(.link)
        #else
        hoverEffect(.highlight)
        #endif
    }
}
