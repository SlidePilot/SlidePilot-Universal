import Observation

/// The sessions of the open documents, so a presentation surface can find the session it
/// shows (DOC-04): the Mac presentation window by ID, the iPad external display by window.
///
/// Owned by the app, not a global: every scene gets it from the app.
@MainActor
@Observable
public final class PresentationRegistry<Session: AnyObject & Identifiable> {
    private struct Entry {
        let session: Session
        var window: String?
    }

    /// In the order of registration.
    private var entries: [Entry] = []
    /// The app window the user worked in last, if the platform reports windows.
    public private(set) var activeWindow: String?

    public init() {}

    /// What a single external display shows: the document of the active window, or `nil`
    /// (the ready screen) if that window shows no document. Before any window is known, the
    /// most recently registered session.
    public var activeSession: Session? {
        if let activeWindow { session(inWindow: activeWindow) } else { entries.last?.session }
    }

    public func session(for id: Session.ID) -> Session? {
        entries.first { $0.session.id == id }?.session
    }

    /// The document shown in an app window, or `nil` if the window shows none.
    public func session(inWindow window: String) -> Session? {
        entries.last { $0.window == window }?.session
    }

    /// Adds a newly opened document's session, or moves a registered one to `window`.
    public func register(_ session: Session, inWindow window: String? = nil) {
        if let index = entries.firstIndex(where: { $0.session.id == session.id }) {
            if let window { entries[index].window = window }
        } else {
            entries.append(Entry(session: session, window: window))
        }
    }

    public func unregister(_ id: Session.ID) {
        entries.removeAll { $0.session.id == id }
    }

    /// Marks the app window the user switched to, e.g. when it becomes the key window.
    public func activateWindow(_ window: String) {
        guard activeWindow != window else { return }
        activeWindow = window
    }
}
