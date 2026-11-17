import SlidePilotRendering
import SwiftUI

/// Content of a document window, the presenter (DOC-04): the current slide and the
/// next-slide preview until the presenter layout (LAY-01).
struct DocumentView: View {
    /// The opened file, watched for recompiles (DOC-08). `nil` when the document system
    /// provides no URL; the PDF is then shown as opened.
    let fileURL: URL?
    @State private var session: PresentationSession
    @FocusState private var hasKeyboardFocus: Bool
    @Environment(SessionRegistry.self) private var registry

    init(document: PDFFileDocument, fileURL: URL? = nil, page: Int = 0) {
        self.fileURL = fileURL
        _session = State(initialValue: PresentationSession(data: document.data, info: document.info, page: page))
    }

    var body: some View {
        CurrentAndNextSlides(session: session)
            .shrinksOnMemoryWarning(session)
            // The presentation surfaces find the session in the registry (DOC-04).
            .onAppear { registry.register(session) }
            .onDisappear { registry.unregister(session.id) }
            #if os(iOS)
            // The iPad external display shows the document of the active window.
            .onAppWindowChange { registry.register(session, inWindow: $0) }
            // How to present on a second screen (#82); the Mac needs no hint.
            .externalDisplayHint()
            #endif
            #if os(macOS)
            .presenterWindow(for: session)
            #endif
            // The session owns the reload on both platforms (ADR 0013). iPadOS also hands the
            // view a new document after a change, macOS does not, so that copy is ignored.
            .task(id: fileURL) {
                guard let fileURL else { return }
                for await version in PDFFileObserver.versions(of: fileURL, current: session.data) {
                    session.reload(with: version)
                }
            }
            // Interim slide change with ← and → until the navigation commands (#17, NAV-01).
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .onAppear { hasKeyboardFocus = true }
            .onKeyPress(.leftArrow) {
                session.showPreviousPage()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                session.showNextPage()
                return .handled
            }
    }
}
