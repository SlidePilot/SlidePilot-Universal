#if os(macOS) && DEBUG
import AppKit

/// Lets the Mac test host launch the test build in light or dark mode without
/// changing the system appearance (ADR 0018). SwiftUI apps ignore the
/// `-AppleInterfaceStyle` launch argument, so the test build reads its own one.
/// Only in Debug builds with the test host's bundle ID suffix.
enum TestHostAppearance {
    static func apply() {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".testhost") == true else { return }
        switch UserDefaults.standard.string(forKey: "SlidePilotTestAppearance") {
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }
}
#endif
