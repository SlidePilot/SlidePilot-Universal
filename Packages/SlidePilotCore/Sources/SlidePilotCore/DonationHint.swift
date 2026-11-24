import Foundation

/// The donation hint of the free Mac download (DROP-03, ADR 0011): the app asks once, after
/// the fifth launch, whether the user would like to support SlidePilot. The App Store build
/// never creates one; the app decides that with a compile-time flag.
///
/// Like the old app, launches are counted up to six only, and the hint is marked as shown
/// as soon as it is presented, so it never appears twice.
@MainActor
public final class DonationHint {
    /// The old app's `UserDefaults` keys.
    public enum Key {
        public static let launchCount = "AppStartCount"
        public static let alreadyShown = "AlreadyDisplayedDonationAlert"
    }

    /// The page the hint and the menu item open, the same as in the old app.
    public static let donationURL = URL(string: "https://slidepilotapp.com/donate.html")!

    /// The launch from which on the hint is due.
    public static let dueLaunch = 5
    /// Counting stops here; higher counts change nothing.
    static let launchCountLimit = 6

    private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
    }

    /// Launches counted so far, at most six.
    public var launchCount: Int {
        store.object(forKey: Key.launchCount) as? Int ?? 0
    }

    /// Whether the hint was presented before.
    public var wasShown: Bool {
        store.object(forKey: Key.alreadyShown) as? Bool ?? false
    }

    /// Counts one app launch. Call it once per launch.
    public func recordLaunch() {
        let count = launchCount
        guard count < Self.launchCountLimit else { return }
        store.set(count + 1, forKey: Key.launchCount)
    }

    /// Whether the hint should be presented now. Returns `true` at most once: the hint is
    /// marked as shown right away, so a second window asking a moment later gets `false`.
    public func presentIfDue() -> Bool {
        guard launchCount >= Self.dueLaunch, !wasShown else { return false }
        store.set(true, forKey: Key.alreadyShown)
        return true
    }
}
