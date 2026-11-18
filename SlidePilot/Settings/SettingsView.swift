import SwiftUI

/// The app settings (SET-01): a tab per pane in the Mac Settings window, one form in the
/// iPad settings sheet.
///
/// Each pane lives in its own file and provides form sections. Later issues add their pane
/// here: Pointer.
struct SettingsView: View {
    #if os(macOS)
    @AppStorage(SettingsTab.storageKey) private var selection = SettingsTab.general
    #else
    /// The pages pushed on the sheet's stack; Edit Layout… opens the sheet on Layout.
    @State private var path: [SettingsTab]

    init(initialTab: SettingsTab? = nil) {
        _path = State(initialValue: initialTab.map { $0 == .general ? [] : [$0] } ?? [])
    }
    #endif

    var body: some View {
        #if os(macOS)
        TabView(selection: $selection) {
            Tab("General", systemImage: "gearshape", value: .general) {
                SettingsPane { GeneralSettingsView() }
            }
            Tab("Layout", systemImage: "rectangle.split.2x1", value: .layout) {
                SettingsPane { LayoutSettingsView() }
            }
            Tab("Remote", systemImage: "antenna.radiowaves.left.and.right", value: .remote) {
                RemoteSettingsPane()
            }
        }
        #else
        NavigationStack(path: $path) {
            Form {
                GeneralSettingsView()
                Section {
                    NavigationLink(value: SettingsTab.layout) {
                        Label("Layout", systemImage: "rectangle.split.2x1")
                    }
                    NavigationLink(value: SettingsTab.remote) {
                        Label("Remote", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsTab.self) { tab in
                switch tab {
                case .layout:
                    Form { LayoutSettingsView() }
                        .navigationTitle("Layout")
                case .remote:
                    RemoteSettingsPane()
                case .general:
                    EmptyView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // The document's navigation would otherwise add a back button to the sheet.
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton()
                }
            }
        }
        // Here, so the pairing code shows on every page of the sheet (REM-02).
        .remoteAlerts()
        #endif
    }
}

#if os(macOS)
/// One tab of the Mac Settings window: a grouped form as wide as the system's own
/// settings panes, as high as its content.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#else
private struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(role: .close) {
            dismiss()
        }
        // Escape closes the sheet with a hardware keyboard.
        .keyboardShortcut(.cancelAction)
    }
}
#endif
