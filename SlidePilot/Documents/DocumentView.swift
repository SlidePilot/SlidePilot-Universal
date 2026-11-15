import SlidePilotRendering
import SwiftUI

/// Content of a document window: the slide navigator as a sidebar (LAY-06), the current
/// slide and the next-slide preview. The presenter layout replaces the detail with #13.
struct DocumentView: View {
    /// The opened file, watched for recompiles (DOC-08). `nil` when the document system
    /// provides no URL; the PDF is then shown as opened.
    let fileURL: URL?
    @State private var session: PresentationSession
    /// The navigator is hidden when a document opens, like in the old app.
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var compactColumn: NavigationSplitViewColumn
    @FocusState private var hasKeyboardFocus: Bool

    init(document: PDFFileDocument, fileURL: URL? = nil, page: Int = 0, showsNavigator: Bool = false) {
        self.fileURL = fileURL
        _session = State(initialValue: PresentationSession(data: document.data, info: document.info, page: page))
        _columnVisibility = State(initialValue: showsNavigator ? .all : .detailOnly)
        _compactColumn = State(initialValue: showsNavigator ? .sidebar : .detail)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            SlideNavigator(session: session)
                // The old navigator was fixed at 180 pt; this one can be resized (LAY-06, changed).
                .navigationSplitViewColumnWidth(min: 120, ideal: 180, max: 360)
        } detail: {
            CurrentAndNextSlides(session: session)
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
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.navigatorVisibility, isNavigatorShown)
        // Esc closes the navigator like in the old app. In the page field, Esc clears it first.
        .onKeyPress(.escape) {
            guard isNavigatorShown.wrappedValue else { return .ignored }
            isNavigatorShown.wrappedValue = false
            return .handled
        }
        .shrinksOnMemoryWarning(session)
        // The session owns the reload on both platforms (ADR 0013). iPadOS also hands the
        // view a new document after a change, macOS does not, so that copy is ignored.
        .task(id: fileURL) {
            guard let fileURL else { return }
            for await version in PDFFileObserver.versions(of: fileURL, current: session.data) {
                session.reload(with: version)
            }
        }
    }

    /// Shows or hides the navigator for View ▸ Show Navigator (O) and Esc.
    private var isNavigatorShown: Binding<Bool> {
        Binding {
            columnVisibility != .detailOnly
        } set: { shown in
            withAnimation {
                columnVisibility = shown ? .all : .detailOnly
                // When the window is too narrow for both columns (iPad), show one of them.
                compactColumn = shown ? .sidebar : .detail
            }
            // Give the arrow keys back to the slides when the navigator closes.
            if !shown { hasKeyboardFocus = true }
        }
    }
}
