import SlidePilotCore
import SlidePilotRendering
import SwiftUI

/// Content of a document window, the presenter (DOC-04), in the presenter layout (LAY-01).
struct DocumentView: View {
    /// The opened file, watched for recompiles (DOC-08). `nil` when the document system
    /// provides no URL; the PDF is then shown as opened.
    let fileURL: URL?
    @State private var session: PresentationSession
    @Environment(SessionRegistry.self) private var registry

    init(
        document: PDFFileDocument,
        fileURL: URL? = nil,
        page: Int = 0,
        layoutStore: any PresenterLayoutStore = UserDefaultsPresenterLayoutStore.app,
        companionStore: CompanionStore? = .app
    ) {
        self.fileURL = fileURL
        _session = State(initialValue: PresentationSession(
            data: document.data, info: document.info, page: page, layoutStore: layoutStore, companionStore: companionStore
        ))
    }

    var body: some View {
        PresenterLayoutView(session: session)
            .presenterLayoutControls(session.layout)
            .shrinksOnMemoryWarning(session)
            .presenterTimer(session)
            .companionFile(session, fileURL: fileURL)
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
                    await session.companion.pdfDidReload(at: fileURL, pageCount: version.info.pageCount)
                }
            }
            // Slide change with keys, menu, toolbar and swipes (NAV-01 to NAV-03).
            .slideNavigationKeys(session)
            .presenterNavigation(session)
    }
}
