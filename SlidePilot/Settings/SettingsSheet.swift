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
    /// Adds the Settings toolbar button and the settings sheet to a document window.
    func settingsSheet() -> some View {
        modifier(SettingsSheetModifier())
    }
}

private struct SettingsSheetModifier: ViewModifier {
    @State private var isShowingSettings = false
    @State private var request = SettingsTabRequest(tab: nil)

    func body(content: Content) -> some View {
        content
            .toolbar {
                // Secondary: inline next to the title in regular width, in the overflow
                // menu when space is short.
                ToolbarItem(placement: .secondaryAction) {
                    Button("Settings", systemImage: "gearshape") {
                        request = SettingsTabRequest(tab: nil)
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(request: request)
            }
            .focusedSceneValue(\.showSettings, ShowSettingsAction { tab in
                // A new request also switches the page while the sheet is open.
                request = SettingsTabRequest(tab: tab)
                isShowingSettings = true
            })
    }
}
#endif
