import SwiftUI

// PROTOTYPE (issue #7).

/// The audience surface: current slide (or the test pattern) on black.
/// Used by the Mac presentation window, the iPad external-display scene and the
/// iPad "presentation window" variant.
struct PresentationView: View {
    let session: PrototypeSession
    /// Names the host in the log, e.g. "external display scene".
    let host: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if session.showTestPattern {
                    TestPatternView()
                } else if session.document != nil {
                    SlideImageView(session: session, pageIndex: session.pageIndex, logsRendering: true)
                }
            }
            .onAppear {
                session.record("\(host): appeared, \(Int(proxy.size.width))×\(Int(proxy.size.height)) pt")
            }
            .onDisappear {
                session.record("\(host): disappeared")
            }
            .onChange(of: proxy.size) { _, size in
                session.record("\(host): resized to \(Int(size.width))×\(Int(size.height)) pt")
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Presentation, slide \(session.pageIndex + 1)"))
        .modifier(PresentationPlatformModifier(session: session))
    }
}
