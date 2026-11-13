import SwiftUI

// PROTOTYPE (issue #7): presenter + presentation scenes. Never merged into main.

enum PrototypeScene {
    static let presentationID = "presentation"
}

@main
struct SlidePilotApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PrototypeAppDelegate.self) private var appDelegate
    #endif

    private let session = PrototypeSession.shared

    var body: some Scene {
        // The prototype replaces main's DocumentGroup so it launches straight into the presenter.
        WindowGroup {
            PresenterView(session: session)
        }
        .commands { PrototypeCommands(session: session) }

        #if os(macOS)
        Window(Text(verbatim: "Presentation"), id: PrototypeScene.presentationID) {
            PresentationView(session: session, host: "mac presentation window")
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .defaultWindowPlacement { _, context in
            MacSwiftUIPlacement.placement(context: context)
        }
        #else
        // Variant for iPadOS windowing with an extended external display:
        // the user drags this window to the external display.
        WindowGroup(Text(verbatim: "Presentation"), id: PrototypeScene.presentationID) {
            PresentationView(session: session, host: "ipad presentation window")
        }
        #endif
    }
}
