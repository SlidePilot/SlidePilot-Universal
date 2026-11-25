import SlidePilotCore
import SwiftUI

/// The two timer warnings (TIME-08) as submenus, next to Set Timer… and Turn Off Timer in the
/// toolbar's Time menu and the Moderator menu (product-owner decision 2026-11-25). They are
/// app-wide settings, so they also work while the stopwatch runs.
struct TimerWarningPickers: View {
    let settings: AppSettings
    /// The toolbar's menu items have symbols; the menu bar's timer items do not.
    var showsSymbols = true

    var body: some View {
        @Bindable var settings = settings
        WarningPicker(minutes: $settings.timerWarnings.firstMinutes, symbol: showsSymbols ? "exclamationmark" : nil) {
            Text("First Warning")
            Text("Timer turns orange")
        }
        WarningPicker(minutes: $settings.timerWarnings.secondMinutes, symbol: showsSymbols ? "exclamationmark.2" : nil) {
            Text("Second Warning")
            Text("Timer turns purple")
        }
    }
}

/// Minutes of remaining time for one timer warning, or Off.
private struct WarningPicker<Title: View>: View {
    @Binding var minutes: Int
    /// The marks of Differentiate Without Color: one for the first warning, two for the second.
    let symbol: String?
    @ViewBuilder let title: Title

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
            if let symbol {
                Label {
                    title
                } icon: {
                    Image(systemName: symbol)
                }
            } else {
                title
            }
        }
        .pickerStyle(.menu)
    }
}
