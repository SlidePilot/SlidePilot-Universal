import SlidePilotCore
import SwiftUI

/// The General pane (SET-05): Keep awake, Crossfade slides and Save drawings.
///
/// The pane only provides form sections; `SettingsView` puts it into a form on each platform.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.keepsDisplayAwake) {
                Text("Keep display awake")
                Text("The display does not dim or sleep while SlidePilot is open.")
            }
            Toggle(isOn: $settings.crossfadesSlides) {
                Text("Crossfade slides")
                Text("Slides fade into each other on the presentation screen.")
            }
            Toggle(isOn: $settings.savesDrawings) {
                Text("Save drawings")
                Text("Drawings stay on their slides and are stored with the PDF. Turning this off deletes all drawings.")
            }
        }
        .onChange(of: settings.savesDrawings) { _, savesDrawings in
            // Open documents delete their own drawings (DRAW-06); this removes the stored
            // drawings of all other PDFs.
            guard !savesDrawings, let store = CompanionStore.app else { return }
            Task { await store.removeAllDrawings() }
        }
    }
}
