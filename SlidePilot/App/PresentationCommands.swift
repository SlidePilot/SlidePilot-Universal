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

/// The Presentation menu. Later issues add navigation, curtain and pointer commands.
struct PresentationCommands: Commands {
    var body: some Commands {
        CommandMenu("Presentation") {
            StartPresentationButton()
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
