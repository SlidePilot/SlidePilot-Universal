import SlidePilotRendering
import SwiftUI

/// Content of a document window: the current slide and the next-slide preview.
/// The presenter layout replaces this with #13.
struct DocumentView: View {
    /// The opened file, watched for recompiles (DOC-08). `nil` when the document system
    /// provides no URL; the PDF is then shown as opened.
    let fileURL: URL?
    @State private var session: PresentationSession
    @FocusState private var hasKeyboardFocus: Bool

    init(document: PDFFileDocument, fileURL: URL? = nil, page: Int = 0) {
        self.fileURL = fileURL
        _session = State(initialValue: PresentationSession(data: document.data, info: document.info, page: page))
    }

    var body: some View {
        CurrentAndNextSlides(session: session)
            .shrinksOnMemoryWarning(session)
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
