import SwiftUI

/// The app settings (SET-01): a tab per pane in the Mac Settings window, one form in the
/// iPad settings sheet.
///
/// Each pane lives in its own file and provides form sections. Later issues add their pane
/// here: Layout (#16) and Pointer.
struct SettingsView: View {
    var body: some View {
        #if os(macOS)
        TabView {
            Tab("General", systemImage: "gearshape") {
                SettingsPane { GeneralSettingsView() }
            }
            Tab("Remote", systemImage: "antenna.radiowaves.left.and.right") {
                RemoteSettingsPane()
            }
        }
        #else
        NavigationStack {
            Form {
                GeneralSettingsView()
                Section {
                    NavigationLink {
                        RemoteSettingsPane()
                    } label: {
                        Label("Remote", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }
            .navigationTitle("Settings")
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
