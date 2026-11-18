#if os(macOS)
import AppKit

/// Saves the documents' companion entries before the app quits (SET-02, NOTES-07): a
/// change from the last half second would otherwise still wait for its delayed save.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let companions = OpenCompanions()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await companions.flushAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
