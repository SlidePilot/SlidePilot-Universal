#if os(macOS)
import AppKit
import SlidePilotCore

/// Applies the Appearance setting (SET-05) to every window of the app. The presentation
/// window and the ready screen set their own dark look and are not affected.
final class AppearanceApplier: AppearanceApplying {
    func apply(_ appearance: AppAppearance) {
        NSApplication.shared.appearance = switch appearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: Self.systemAppearance
        }
    }

    /// The test build follows the test host's launch appearance instead of the system's.
    private static var systemAppearance: NSAppearance? {
        #if DEBUG
        TestHostAppearance.launchAppearance
        #else
        nil
        #endif
    }
}
#endif
