#if os(iOS)
import SwiftUI

/// Opens the settings sheet of the focused document window (SET-01, iPad).
struct ShowSettingsAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

extension FocusedValues {
    @Entry var showSettings: ShowSettingsAction?
}

/// Settings… (⌘,) in the app menu of the iPad menu bar, where the Mac has it too.
struct SettingsCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            SettingsMenuButton()
        }
    }
}

private struct SettingsMenuButton: View {
    @FocusedValue(\.showSettings) private var showSettings

    var body: some View {
        Button("Settings…") {
            showSettings?()
        }
        .keyboardShortcut(",", modifiers: .command)
        .disabled(showSettings == nil)
    }
}

extension View {
    /// Adds the Settings toolbar button and the settings sheet to a document window.
    func settingsSheet() -> some View {
        modifier(SettingsSheetModifier())
    }
}

private struct SettingsSheetModifier: ViewModifier {
    @State private var isShowingSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                // Secondary: inline next to the title in regular width, in the overflow
                // menu when space is short.
                ToolbarItem(placement: .secondaryAction) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .focusedSceneValue(\.showSettings, ShowSettingsAction { isShowingSettings = true })
    }
}
#endif
