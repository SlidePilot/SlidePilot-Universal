import SlidePilotCore
import SwiftUI

/// The Moderator menu, like the old app's. Later issues add layout, navigator and drawing
/// commands as their own item views.
struct ModeratorCommands: Commands {
    let settings: AppSettings

    var body: some Commands {
        CommandMenu("Moderator") {
            NavigatorMenuItems()
            Divider()
            DrawingMenuItems()
            Divider()
            TimerMenuItems(settings: settings)
        }
    }
}

/// Set Timer, Turn Off Timer, Start/Stop Time and Reset Time with the old app's
/// plain-letter shortcuts (TIME-02 to TIME-04). Set Timer also changes a running timer.
/// The timer warnings (TIME-08) are app-wide, so they work without a document too.
private struct TimerMenuItems: View {
    let settings: AppSettings
    @FocusedValue(\.presenterTimer) private var timer

    var body: some View {
        Button("Set Timer…") {
            timer?.showSetTimer?()
        }
        .plainKeyShortcut("t")
        .disabled(timer?.showSetTimer == nil)

        if let timer {
            TurnOffTimerButton(session: timer.session)
        } else {
            Button("Turn Off Timer") {}
                .disabled(true)
        }
        TimerWarningPickers(settings: settings, showsSymbols: false)

        Button("Start/Stop Time") {
            timer?.session.timer.toggle()
        }
        .plainKeyShortcut("s")
        .disabled(timer == nil)

        Button("Reset Time") {
            timer?.session.timer.reset()
        }
        .plainKeyShortcut("r")
        .disabled(timer == nil)
    }
}
