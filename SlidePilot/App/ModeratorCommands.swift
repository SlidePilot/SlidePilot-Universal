import SwiftUI

/// The Moderator menu, like the old app's. Later issues add layout, navigator and drawing
/// commands as their own item views.
struct ModeratorCommands: Commands {
    var body: some Commands {
        CommandMenu("Moderator") {
            NavigatorMenuItems()
            Divider()
            TimerMenuItems()
        }
    }
}

/// Mode, Set Timer, Start/Stop Time and Reset Time with the old app's plain-letter
/// shortcuts (TIME-02 to TIME-04).
private struct TimerMenuItems: View {
    @FocusedValue(\.presenterTimer) private var timer

    var body: some View {
        if let timer {
            TimeModePicker(session: timer.session)
        } else {
            Picker("Mode", selection: .constant(0)) {}
                .disabled(true)
        }
        Button("Set Timer…") {
            timer?.showSetTimer?()
        }
        .plainKeyShortcut("t")
        .disabled(timer?.showSetTimer == nil || timer?.session.timer.mode != .timer)

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
