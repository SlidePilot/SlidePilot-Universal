import SwiftUI

/// Starts the presentation of the focused document window (DOC-05, changed).
struct StartPresentationAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

extension FocusedValues {
    @Entry var startPresentation: StartPresentationAction?
}

extension EnvironmentValues {
    /// The same action for the presenter's toolbar, which focused values do not reliably reach.
    @Entry var startPresentation: StartPresentationAction?
}

/// The Presentation menu.
struct PresentationCommands: Commands {
    var body: some Commands {
        CommandMenu("Presentation") {
            SlideNavigationMenuItems()
            Divider()
            CurtainMenuItems()
            Divider()
            PointerMenuItems()
            #if os(macOS)
            Divider()
            StartPresentationButton()
            #endif
        }
    }
}

private struct StartPresentationButton: View {
    @FocusedValue(\.startPresentation) private var startPresentation

    var body: some View {
        Button("Start Presentation") {
            startPresentation?()
        }
        .keyboardShortcut("p", modifiers: [.command, .option])
        .disabled(startPresentation == nil)
    }
}
