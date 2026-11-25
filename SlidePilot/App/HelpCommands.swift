import SwiftUI

/// The online user guide, which the old app opened from Help ▸ SlidePilot Help (SET-06).
enum HelpWebsite {
    static let url = URL(string: "https://docs.slidepilotapp.com")!
}

/// Help ▸ SlidePilot Help (⌘?) opens the online user guide (SET-06), in place of the
/// system item that reports that no help is available. The Mac keeps the menu's search field.
struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            HelpMenuButton()
        }
    }
}

private struct HelpMenuButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("SlidePilot Help") {
            openURL(HelpWebsite.url)
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

#if os(iOS)
/// The settings sheet's link to the online user guide (SET-06), since the iPhone has no
/// menu bar and the iPad shows it only with a hardware keyboard.
struct HelpSection: View {
    var body: some View {
        Section {
            Link(destination: HelpWebsite.url) {
                Label("SlidePilot Help", systemImage: "questionmark.circle")
            }
        }
    }
}
#endif
