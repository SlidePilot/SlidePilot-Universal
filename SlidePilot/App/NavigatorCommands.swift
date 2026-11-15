import SwiftUI

extension FocusedValues {
    /// Whether the focused presenter shows the slide navigator (LAY-06).
    @Entry var navigatorVisibility: Binding<Bool>?
}

/// View ▸ Show Navigator with the old shortcut O. Esc in the presenter closes it too.
struct NavigatorCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ShowNavigatorToggle()
        }
    }
}

private struct ShowNavigatorToggle: View {
    @FocusedValue(\.navigatorVisibility) private var isShown

    var body: some View {
        Toggle("Show Navigator", isOn: isShown ?? .constant(false))
            .keyboardShortcut("o", modifiers: [])
            .disabled(isShown == nil)
    }
}
