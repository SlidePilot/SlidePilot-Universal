import Observation

/// Whether an external display is connected, as seen by the iPad's external-display scenes
/// (DOC-05). Owned by the app; the scenes report themselves by their session ID.
///
/// A set, not a flag: on iPadOS 27 the system swaps one window's display scene for
/// another's, and the new scene may connect before the old one disconnects.
@MainActor
@Observable
public final class ExternalDisplayStatus {
    private var scenes: Set<String> = []

    public init() {}

    /// `true` while at least one external-display scene is connected.
    public var isConnected: Bool { !scenes.isEmpty }

    /// Records a connected external-display scene. Returns `true` if it is the first one.
    @discardableResult
    public func connect(_ scene: String) -> Bool {
        let wasConnected = isConnected
        scenes.insert(scene)
        return !wasConnected
    }

    public func disconnect(_ scene: String) {
        scenes.remove(scene)
    }
}
