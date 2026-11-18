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

    init(document: PDFFileDocument, fileURL: URL? = nil, page: Int = 0, layoutStore: any PresenterLayoutStore = UserDefaultsPresenterLayoutStore.app) {
        self.fileURL = fileURL
        _session = State(initialValue: PresentationSession(data: document.data, info: document.info, page: page, layoutStore: layoutStore))
    }

    var body: some View {
        // The navigator sidebar (LAY-06) next to the slides.
        SlideNavigatorSplitView(
            session: session,
            slidesChrome: PresenterClock(session: session),
            chrome: PresenterChrome(session: session)
        ) {
            PresenterLayoutView(session: session)
        }
            .shrinksOnMemoryWarning(session)
            // The presentation surfaces find the session in the registry (DOC-04).
            .onAppear { registry.register(session) }
            .onDisappear { registry.unregister(session.id) }
            #if os(iOS)
            // The iPad external display shows the document of the active window.
            .onAppWindowChange { registry.register(session, inWindow: $0) }
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
            // Slide change with keys, menu, toolbar and swipes (NAV-01 to NAV-03).
            .slideNavigationKeys(session)
            .navigatorEscapeKey(session)
            // The "." key must wrap the view that holds the keyboard (CUR-01).
            .blackCurtainKey(session)
    }
}

/// The clock above the slides.
private struct PresenterClock: ViewModifier {
    let session: PresentationSession

    func body(content: Content) -> some View {
        content.presenterTimeDisplay(session)
    }
}

/// The presenter's toolbar items, menu commands and swipes. `SlideNavigatorSplitView` puts
/// them on the slides column (Mac) or on the document's bar (iPad).
private struct PresenterChrome: ViewModifier {
    let session: PresentationSession

    func body(content: Content) -> some View {
        content
            .presenterLayoutControls(session.layout)
            .presenterTimerControls(session)
            .presenterNavigation(session)
            // Black and white curtain and its warning (CUR-01, CUR-02).
            .presenterCurtain(session)
            #if os(iOS)
            // How to present on a second screen (#82); the Mac needs no hint.
            .externalDisplayHint()
            // The Mac has the Settings window instead (SET-01).
            .settingsSheet()
            #endif
    }
}
