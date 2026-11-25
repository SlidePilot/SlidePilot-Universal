import SlidePilotCore
import SwiftUI

/// The Layout pane (LAY-04, TIME-06, TIME-08): padding around the presenter's slots, the
/// size of the time display and the timer warnings. All are global (LAY-05). Replaces the
/// old drag-and-drop layout editor with standard pickers (ADR 0010).
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
                Text("Size of the clock and timer above the slides.")
            }
        }
        // TIME-08: the timer changes color as its end comes closer.
        Section {
            WarningPicker(minutes: $settings.timerWarnings.firstMinutes) {
                Text("First warning")
                Text("The timer turns orange.")
            }
            WarningPicker(minutes: $settings.timerWarnings.secondMinutes) {
                Text("Second warning")
                Text("The timer turns purple. In overtime it is red.")
            }
        } header: {
            Text("Timer")
        } footer: {
            Text("Remaining time at which the timer changes color. Only in timer mode, not for the stopwatch.")
        }
    }
}

/// Minutes of remaining time for one timer warning, or Off.
private struct WarningPicker<Label: View>: View {
    @Binding var minutes: Int
    @ViewBuilder let label: Label

    var body: some View {
        Picker(selection: $minutes) {
            ForEach(TimerWarningThresholds.choices, id: \.self) { choice in
                if choice == 0 {
                    Text("Off").tag(choice)
                } else {
                    Text(Duration.seconds(choice * 60).formatted(.units(allowed: [.minutes], width: .abbreviated)))
                        .tag(choice)
                }
            }
        } label: {
            label
        }
    }
}

/// The settings panes, so a command can open a specific one (LAY-04: Edit Layout…,
/// PTR-04: Edit Pointer…).
enum SettingsTab: String, Hashable {
    case general
    case layout
    case pointer
    case remote
    /// The stored data overview (SET-07); a page of the iPad sheet, a sheet of the General
    /// tab on the Mac.
    case storedData

    /// The Mac Settings window's selected tab, so Edit Layout… can switch to Layout while
    /// the window is open.
    static let storageKey = "selectedSettingsTab"
}

private extension LayoutPadding {
    /// Own keys, because French needs other forms here than for the time display sizes.
    var title: LocalizedStringResource {
        switch self {
        case .none: LocalizedStringResource("Padding.None", defaultValue: "None")
        case .small: LocalizedStringResource("Padding.Small", defaultValue: "Small")
        case .normal: LocalizedStringResource("Padding.Normal", defaultValue: "Normal")
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
