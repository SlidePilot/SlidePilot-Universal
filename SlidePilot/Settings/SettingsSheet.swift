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

extension EnvironmentValues {
    /// For the presenter toolbar's Settings button, which needs the action of its own window.
    @Entry var showSettings: ShowSettingsAction?
}

/// Settings in the presenter's toolbar (SET-01, iPhone and iPad); `PresenterToolbar` places it.
struct SettingsToolbarButton: View {
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        Button("Settings", systemImage: "gearshape") {
            showSettings?()
        }
        .disabled(showSettings == nil)
    }
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
    /// Adds the settings sheet to a document window; `SettingsToolbarButton` opens it.
    func settingsSheet() -> some View {
        modifier(SettingsSheetModifier())
    }
}

private struct SettingsSheetModifier: ViewModifier {
    @State private var isShowingSettings = false

    func body(content: Content) -> some View {
        content
            .environment(\.showSettings, showSettings)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .focusedSceneValue(\.showSettings, showSettings)
    }

    private var showSettings: ShowSettingsAction {
        ShowSettingsAction {
            isShowingSettings = true
        }
    }
}
#endif
