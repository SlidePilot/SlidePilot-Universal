import SlidePilotCore
import SwiftUI

/// The General pane (SET-05): Appearance, Keep awake, Crossfade slides and Save drawings.
///
/// The pane only provides form sections; `SettingsView` puts it into a form on each platform.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    /// Turning "Save drawings" off deletes every drawing, so it is confirmed first (DRAW-06).
    @State private var confirmsDeletingDrawings = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            Toggle(isOn: $settings.keepsDisplayAwake) {
                Text("Keep display awake")
                Text("The display does not dim or sleep while SlidePilot is open.")
            }
            Toggle(isOn: $settings.crossfadesSlides) {
                Text("Crossfade slides")
                Text("Slides fade into each other on the presentation screen.")
            }
            Toggle(isOn: savesDrawings) {
                Text("Save drawings")
                Text("Drawings stay on their slides and are stored with the PDF. Turning this off deletes all drawings.")
            }
        }
        .alert("Delete all drawings?", isPresented: $confirmsDeletingDrawings) {
            Button("Delete Drawings", role: .destructive) {
                settings.savesDrawings = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turning off Save drawings deletes the drawings of all PDFs. This cannot be undone.")
        }
        .onChange(of: settings.savesDrawings) { _, savesDrawings in
            // Open documents delete their own drawings (DRAW-06); this removes the stored
            // drawings of all other PDFs.
            guard !savesDrawings, let store = CompanionStore.app else { return }
            Task { await store.removeAllDrawings() }
        }
    }

    /// Turns the setting on at once; turning it off waits for the confirmation.
    private var savesDrawings: Binding<Bool> {
        Binding {
            settings.savesDrawings
        } set: { newValue in
            if newValue {
                settings.savesDrawings = true
            } else if settings.savesDrawings {
                confirmsDeletingDrawings = true
            }
        }
    }
}

private extension AppAppearance {
    var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("Appearance.System", defaultValue: "System")
        case .light: LocalizedStringResource("Appearance.Light", defaultValue: "Light")
        case .dark: LocalizedStringResource("Appearance.Dark", defaultValue: "Dark")
        }
    }
}
