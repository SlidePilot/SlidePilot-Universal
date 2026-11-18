#if os(iOS)
import SlidePilotCore
import UIKit

/// Keeps the iPad's display awake by turning off the idle timer (SET-04). The system only
/// applies it while the app is in the foreground. The idle timer is app-wide, so only one
/// blocker may exist (the app delegate's keeper owns it).
final class DisplaySleepBlocker: DisplaySleepBlocking {
    var isBlocking: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }

    isolated deinit {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
#endif
