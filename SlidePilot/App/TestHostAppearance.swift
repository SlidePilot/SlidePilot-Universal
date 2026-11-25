#if os(macOS) && DEBUG
import AppKit

/// Lets the Mac test host launch the test build in light or dark mode without
/// changing the system appearance (ADR 0018). SwiftUI apps ignore the
/// `-AppleInterfaceStyle` launch argument, so the test build reads its own one.
/// Only in Debug builds with the test host's bundle ID suffix. The Appearance setting
/// (SET-05) uses it in place of the system appearance.
enum TestHostAppearance {
    static var launchAppearance: NSAppearance? {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".testhost") == true else { return nil }
        switch UserDefaults.standard.string(forKey: "SlidePilotTestAppearance") {
        case "dark": return NSAppearance(named: .darkAqua)
        case "light": return NSAppearance(named: .aqua)
        default: return nil
        }
    }
}
#endif
