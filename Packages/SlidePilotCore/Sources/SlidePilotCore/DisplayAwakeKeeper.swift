import Observation

/// Keeps the display from sleeping or dimming while it blocks (SET-04).
///
/// The app provides one per platform: an IOPM `NoDisplaySleep` assertion on the Mac and
/// the idle timer on iPad.
@MainActor
public protocol DisplaySleepBlocking: AnyObject {
    var isBlocking: Bool { get set }
}

/// Follows the Keep display awake setting (SET-04) for as long as it lives.
///
/// The app owns one for its whole run, like the old app's `AwakeManager`. Releasing the
/// keeper stops following the setting and lets the display sleep again.
@MainActor
public final class DisplayAwakeKeeper {
    private let blocker: any DisplaySleepBlocking
    private var observation: Task<Void, Never>?

    public init(settings: AppSettings, blocker: any DisplaySleepBlocking) {
        self.blocker = blocker
        // Applied right away, so the display is kept awake from launch on.
        blocker.isBlocking = settings.keepsDisplayAwake
        observation = Task { [blocker] in
            for await keepsAwake in Observations({ settings.keepsDisplayAwake }) {
                // A value queued before the keeper went must not block again after its deinit.
                guard !Task.isCancelled else { break }
                blocker.isBlocking = keepsAwake
            }
        }
    }

    isolated deinit {
        observation?.cancel()
        blocker.isBlocking = false
    }
}
