import SwiftUI

/// The Moderator menu, like the old app's. Later issues add layout, navigator and drawing
/// commands as their own item views.
struct ModeratorCommands: Commands {
    var body: some Commands {
        CommandMenu("Moderator") {
            EditLayoutMenuItem()
            Divider()
            NavigatorMenuItems()
            Divider()
            DrawingMenuItems()
            Divider()
            TimerMenuItems()
        }
    }
}

/// Opens the Layout settings (LAY-04), with the old app's shortcut ⌃⌥L.
private struct EditLayoutMenuItem: View {
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general
    #else
    @FocusedValue(\.showSettings) private var showSettings
    #endif

    var body: some View {
        #if os(macOS)
        Button("Edit Layout…") {
            settingsTab = .layout
            openSettings()
        }
        .keyboardShortcut("l", modifiers: [.control, .option])
        #else
        Button("Edit Layout…") {
            showSettings?(.layout)
        }
        .keyboardShortcut("l", modifiers: [.control, .option])
        .disabled(showSettings == nil)
        #endif
    }
}

/// Set Timer, Turn Off Timer, Start/Stop Time and Reset Time with the old app's
/// plain-letter shortcuts (TIME-02 to TIME-04). Set Timer also changes a running timer.
private struct TimerMenuItems: View {
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
