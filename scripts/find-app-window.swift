// Prints the window ID of the frontmost on-screen window that belongs to a
// SlidePilot process started from an Xcode build folder (DerivedData /
// Build/Products). Other apps, including an installed SlidePilot 1.8, are
// never matched. Exits with status 1 if no such window exists.
import AppKit
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

for window in windows {
    guard (window[kCGWindowLayer as String] as? Int) == 0,
          let pid = window[kCGWindowOwnerPID as String] as? pid_t,
          let app = NSRunningApplication(processIdentifier: pid),
          let path = app.bundleURL?.path,
          path.contains("/Build/Products/"),
          path.hasSuffix("/SlidePilot.app"),
          let id = window[kCGWindowNumber as String] as? Int
    else { continue }
    print(id)
    exit(0)
}
exit(1)
