#if os(macOS)
import AppKit
import SlidePilotCore

/// Saves the documents' companion entries before the app quits (SET-02, NOTES-07): a
/// change from the last half second would otherwise still wait for its delayed save.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let companions = OpenCompanions()
    /// The donation hint; only the free download has one (DROP-03, ADR 0011).
    let donationHint: DonationHint? = ProductEdition.showsDonationHint
        ? DonationHint(store: UserDefaults.standard) : nil

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await companions.flushAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Keeps Save and the other saving items out of the File menu (#136).
    private let fileMenu = ViewerFileMenu()

    func applicationWillFinishLaunching(_ notification: Notification) {
        fileMenu.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        donationHint?.recordLaunch()
    }
}
#endif
