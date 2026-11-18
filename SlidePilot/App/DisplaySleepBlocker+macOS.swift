#if os(macOS)
import IOKit.pwr_mgt
import SlidePilotCore

/// Keeps the Mac's display awake with an IOPM `NoDisplaySleep` assertion (SET-04).
final class DisplaySleepBlocker: DisplaySleepBlocking {
    /// The held assertion; `nil` while the display may sleep.
    private var assertion: IOPMAssertionID?

    var isBlocking: Bool {
        get { assertion != nil }
        set { newValue ? acquire() : release() }
    }

    private func acquire() {
        guard assertion == nil else { return }
        var id: IOPMAssertionID = 0
        // Shown by `pmset -g assertions`; not part of the UI, so not localized.
        let reason = "SlidePilot keeps the display awake during presentations." as CFString
        guard IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        ) == kIOReturnSuccess else { return }
        assertion = id
    }

    private func release() {
        guard let assertion else { return }
        IOPMAssertionRelease(assertion)
        self.assertion = nil
    }

    isolated deinit {
        release()
    }
}
#endif
