import Observation

/// The sessions of the open documents, so a presentation surface can find the session it
/// shows (DOC-04): the Mac presentation window by ID, the iPad external display by recency.
///
/// Owned by the app, not a global: every scene gets it from the app.
@MainActor
@Observable
public final class PresentationRegistry<Session: AnyObject & Identifiable> {
    /// Least recently active first.
    private var sessions: [Session] = []

    public init() {}

    /// The most recently activated or registered session, or `nil` if no document is open.
    public var activeSession: Session? { sessions.last }

    public func session(for id: Session.ID) -> Session? {
        sessions.first { $0.id == id }
    }

    /// Adds a newly opened document's session; it becomes the active session.
    public func register(_ session: Session) {
        guard self.session(for: session.id) == nil else { return }
        sessions.append(session)
    }

    public func unregister(_ id: Session.ID) {
        sessions.removeAll { $0.id == id }
    }

    /// Makes a registered session the active one, e.g. when its window comes to the front.
    public func activate(_ id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), index != sessions.count - 1 else { return }
        sessions.append(sessions.remove(at: index))
    }
}
