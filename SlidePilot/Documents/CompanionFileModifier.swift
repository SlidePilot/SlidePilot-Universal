import SlidePilotCore
import SwiftUI

extension CompanionStore {
    /// The app's companion entries in Application Support (ADR 0012). `nil` if the folder
    /// cannot be created; documents then open without stored data.
    static let app: CompanionStore? = try? CompanionStore.appContainer()

    /// Removes settings-only entries that were not opened for 12 months (SET-03).
    static func cleanUpAtLaunch() {
        guard let app else { return }
        Task { await app.removeExpiredEntries() }
    }
}

extension View {
    /// Loads and saves the document's companion entry: per-document settings (SET-02), the
    /// orphaned data hint (NOTES-12) and the document-edited indicator (DOC-09).
    func companionFile(_ session: PresentationSession, fileURL: URL?) -> some View {
        modifier(CompanionFileModifier(session: session, fileURL: fileURL))
    }
}

private struct CompanionFileModifier: ViewModifier {
    let session: PresentationSession
    let fileURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @State private var window: NSWindow?
    #endif

    private var companion: DocumentCompanion { session.companion }

    func body(content: Content) -> some View {
        content
            // Settings are applied at the end of opening (SET-02).
            .task(id: fileURL) {
                guard let fileURL else { return }
                let settings = await companion.open(pdfAt: fileURL, pageCount: session.cache.info.pageCount)
                apply(settings)
                session.layout.onChange = { [companion] layout in
                    companion.updateSettings { $0.layout = layout }
                }
            }
            .alert(
                Text("Use Data from a Missing PDF?"),
                isPresented: Binding(get: { companion.orphan != nil }, set: { _ in }),
                presenting: companion.orphan
            ) { _ in
                Button("Use Data") {
                    Task {
                        if let settings = await companion.takeOverOrphan() {
                            apply(settings)
                        }
                    }
                }
                Button("Don’t Use", role: .cancel) {
                    Task { await companion.declineOrphan() }
                }
            } message: { orphan in
                Text("SlidePilot has stored data for a PDF named “\(orphan.pdf.fileName)” with the same number of pages that can no longer be found. You can use it for this PDF.")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    Task { await companion.flush() }
                }
            }
            .onDisappear {
                Task { [companion] in await companion.flush() }
            }
            #if os(macOS)
            // The presenter window shows the system's edited dot in its close button (DOC-09).
            .background(WindowBridge { newWindow in
                window = newWindow
                newWindow.isDocumentEdited = companion.isEdited
            })
            .onChange(of: companion.isEdited) { _, isEdited in
                window?.isDocumentEdited = isEdited
            }
            #endif
    }

    private func apply(_ settings: DocumentSettings) {
        if let layout = settings.layout {
            session.layout.applyStoredLayout(layout)
        }
    }
}
