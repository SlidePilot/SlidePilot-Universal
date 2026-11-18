import SlidePilotCore
import SwiftUI

/// The Layout pane (LAY-04, TIME-06): padding around the presenter's slots and the size of
/// the time display. Both are global (LAY-05). Replaces the old drag-and-drop layout editor
/// with standard pickers (ADR 0010).
///
/// The pane only provides form sections; `SettingsView` puts it into a form on each platform.
struct LayoutSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker(selection: $settings.layoutPadding) {
                ForEach(LayoutPadding.allCases, id: \.self) { padding in
                    Text(padding.title).tag(padding)
                }
            } label: {
                Text("Slide padding")
                Text("Space around each slide in the presenter view.")
            }
            Picker(selection: $settings.timeDisplaySize) {
                ForEach(TimeDisplaySize.allCases, id: \.self) { size in
                    Text(size.title).tag(size)
                }
            } label: {
                Text("Time display")
                Text("Size of the clock and the stopwatch or timer above the slides.")
            }
        }
    }
}

/// The settings panes, so a command can open a specific one (LAY-04: Edit Layout…).
enum SettingsTab: String, Hashable {
    case general
    case layout
    case remote

    /// The Mac Settings window's selected tab, so Edit Layout… can switch to Layout while
    /// the window is open.
    static let storageKey = "selectedSettingsTab"
}

private extension LayoutPadding {
    var title: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .small: "Small"
        case .normal: "Normal"
        }
    }
}

private extension TimeDisplaySize {
    var title: LocalizedStringKey {
        switch self {
        case .hidden: "Hidden"
        case .small: "Small"
        case .normal: "Normal"
        }
    }
}
