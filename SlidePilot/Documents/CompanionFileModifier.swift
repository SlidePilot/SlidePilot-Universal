import SlidePilotCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

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

/// The companions of the open documents, so the Mac can save them before the app quits.
@MainActor
@Observable
final class OpenCompanions {
    @ObservationIgnored private var companions: [ObjectIdentifier: DocumentCompanion] = [:]

    func add(_ companion: DocumentCompanion) {
        companions[ObjectIdentifier(companion)] = companion
    }

    func remove(_ companion: DocumentCompanion) {
        companions[ObjectIdentifier(companion)] = nil
    }

    func flushAll() async {
        for companion in companions.values {
            await companion.flush()
        }
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
    /// Provided on the Mac only; iPadOS saves when the app leaves the foreground.
    @Environment(OpenCompanions.self) private var openCompanions: OpenCompanions?
    #if os(macOS)
    @State private var window: NSWindow?
    #endif

    private var companion: DocumentCompanion { session.companion }

    func body(content: Content) -> some View {
        content
            // Settings are applied at the end of opening (SET-02). Layout changes made while
            // the entry loads are kept and win over the stored layout.
            .task(id: fileURL) {
                guard let fileURL else { return }
                session.layout.onChange = { [companion] layout in
                    companion.updateSettings { $0.layout = layout }
                }
                let settings = await companion.open(pdfAt: fileURL, pageCount: session.cache.info.pageCount)
                if let settings, !Task.isCancelled {
                    apply(settings)
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
                Text("A PDF named “\(orphan.pdf.fileName)” with the same number of pages can no longer be found. You can use its stored data for this PDF.")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    saveInBackground(companion)
                }
            }
            .onAppear { openCompanions?.add(companion) }
            .onDisappear {
                // Removed only after the save, so quitting right after closing still waits for it.
                saveInBackground(companion) { [openCompanions] in
                    openCompanions?.remove(companion)
                }
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

    /// Saves pending changes. On iPadOS the system keeps the app running until the write
    /// finished, also when it moves to the background.
    private func saveInBackground(_ companion: DocumentCompanion, then completion: @escaping @MainActor () -> Void = {}) {
        #if os(iOS)
        let application = UIApplication.shared
        let backgroundTask = BackgroundTask()
        backgroundTask.id = application.beginBackgroundTask(withName: "Save document data") {
            // Out of time: end the task, so the system suspends the app instead of ending it.
            backgroundTask.end()
        }
        Task {
            await companion.flush()
            completion()
            backgroundTask.end()
        }
        #else
        Task {
            await companion.flush()
            completion()
        }
        #endif
    }

    private func apply(_ settings: DocumentSettings) {
        if let layout = settings.layout {
            session.layout.applyStoredLayout(layout)
        }
    }
}

#if os(iOS)
/// The identifier of a background task, shared by the save and the expiration handler.
private final class BackgroundTask {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif
