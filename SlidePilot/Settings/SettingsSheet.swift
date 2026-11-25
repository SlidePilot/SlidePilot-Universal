#if os(iOS)
import SwiftUI

/// Opens the settings sheet of the focused document window (SET-01, iPad).
struct ShowSettingsAction {
    let perform: (SettingsTab?) -> Void

    /// Opens the sheet, on `tab` if given (Edit Layout… opens it on Layout, LAY-04).
    func callAsFunction(_ tab: SettingsTab? = nil) {
        perform(tab)
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

/// One request to show the settings sheet on a page. Each request is new, so asking for
/// the same page again still switches back to it.
struct SettingsTabRequest: Equatable {
    let tab: SettingsTab?
    private let id = UUID()

    init(tab: SettingsTab?) {
        self.tab = tab
    }

    /// The sheet's navigation path for this request; General is the root page.
    var path: [SettingsTab] {
        tab.map { $0 == .general ? [] : [$0] } ?? []
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
    @State private var request = SettingsTabRequest(tab: nil)

    func body(content: Content) -> some View {
        content
            .environment(\.showSettings, showSettings)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(request: request)
            }
            .focusedSceneValue(\.showSettings, showSettings)
    }

    private var showSettings: ShowSettingsAction {
        ShowSettingsAction { tab in
            // A new request also switches the page while the sheet is open.
            request = SettingsTabRequest(tab: tab)
            isShowingSettings = true
        }
    }
}
#endif
