import SlidePilotCore
import SwiftUI

/// The General pane (SET-05): Keep awake and Crossfade slides.
///
/// The behavior behind both toggles comes with #23; Save drawings comes with the drawing
/// issue (DRAW-06). The pane only provides form sections; `SettingsView` puts it into a
/// form on each platform.
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
        }
    }
}
