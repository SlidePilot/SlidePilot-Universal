import SlidePilotCore
import SwiftUI

/// The timer of the focused presenter window, for the Moderator menu (TIME-02 to TIME-04).
struct FocusedPresenterTimer {
    let session: PresentationSession
    /// `nil` in the Mac presentation window: the Set Timer sheet belongs to the presenter.
    let showSetTimer: (() -> Void)?
}

extension FocusedValues {
    @Entry var presenterTimer: FocusedPresenterTimer?
}

extension View {
    /// The clock and the stopwatch/timer above the slides.
    func presenterTimeDisplay(_ session: PresentationSession) -> some View {
        modifier(PresenterTimeDisplayModifier(session: session))
    }

    /// The timer's toolbar controls, the Set Timer sheet and the menu commands. Separate
    /// from the display because on iPad the navigator puts them on another view (LAY-06).
    func presenterTimerControls(_ session: PresentationSession) -> some View {
        modifier(PresenterTimerModifier(session: session))
    }
}

private struct PresenterTimeDisplayModifier: ViewModifier {
    let session: PresentationSession
    // TIME-06: global, set in the Layout settings (LAY-04). Optional, so snapshots and
    // previews without settings use the default.
    @Environment(AppSettings.self) private var settings: AppSettings?
    @Environment(\.isCompactHeight) private var isCompactHeight
    @Environment(\.presenterMakesRoomForDrawing) private var makesRoomForDrawing

    private var size: TimeDisplaySize { settings?.timeDisplaySize ?? .default }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                // Drawing on iPhone and iPad gives the slide the room of the clock (#152).
                if size != .hidden, !makesRoomForDrawing {
                    TimeDisplay(timer: session.timer, size: size)
                        // Aligned with the slides' 30 pt padding; the old app's top margin,
                        // the small one in compact height like the smaller display there.
                        .padding(.horizontal, 30)
                        .padding(.top, size == .small || isCompactHeight ? 5 : 20)
                }
            }
    }
}

private struct PresenterTimerModifier: ViewModifier {
    let session: PresentationSession
    @State private var isSettingTimer = false
    @Environment(\.presenterToolbarFocus) private var focus

    func body(content: Content) -> some View {
        content
            .toolbar {
                TimerToolbar(session: session, isSettingTimer: $isSettingTimer, placement: focus.placement())
            }
            .sheet(isPresented: $isSettingTimer) {
                SetTimerSheet(duration: session.timer.timerDuration) { seconds in
                    session.timer.setTimer(seconds: seconds)
                }
            }
            // While the sheet is open, the plain-letter shortcuts must not fire from its
            // text fields, so the menu commands are off.
            .focusedSceneValue(\.presenterTimer, isSettingTimer ? nil : FocusedPresenterTimer(
                session: session,
                showSetTimer: { isSettingTimer = true }
            ))
    }
}

/// Timer toggle, Start/Stop and Reset in the presenter's toolbar (TIME-02 to TIME-04).
private struct TimerToolbar: ToolbarContent {
    let session: PresentationSession
    @Binding var isSettingTimer: Bool
    let placement: ToolbarItemPlacement

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            TimerToggle(session: session, isSettingTimer: $isSettingTimer)
            StartStopTimeButton(session: session)
            ResetTimeButton(session: session)
        }
    }
}

/// Shows whether the timer is on (TIME-04, changed). Switching it on asks for the time;
/// the timer is on once a time above zero is set. Switching it off goes back to the stopwatch.
/// Moderator > Set Timer… (T) changes a running timer without switching it off; toolbar
/// items get no context menu (a right click or long press shows the toolbar's own menu or
/// acts as a tap).
private struct TimerToggle: View {
    let session: PresentationSession
    @Binding var isSettingTimer: Bool

    var body: some View {
        let isOn = session.timer.mode == .timer
        Toggle("Timer", systemImage: "timer", isOn: Binding(
            get: { isOn },
            set: { turnOn in
                if turnOn {
                    isSettingTimer = true
                } else {
                    session.timer.turnOffTimer()
                }
            }
        ))
        .help(isOn ? Text("Turn Off Timer") : Text("Set Timer…"))
    }
}

/// Back to the stopwatch (TIME-04, changed), in the Moderator menu.
struct TurnOffTimerButton: View {
    let session: PresentationSession

    var body: some View {
        Button("Turn Off Timer") {
            session.timer.turnOffTimer()
        }
        .disabled(session.timer.mode != .timer)
    }
}

struct StartStopTimeButton: View {
    let session: PresentationSession

    var body: some View {
        let isRunning = session.timer.isRunning
        Button {
            session.timer.toggle()
        } label: {
            Label(
                isRunning ? "Stop Time" : "Start Time",
                systemImage: isRunning ? "pause.fill" : "play.fill"
            )
        }
    }
}

struct ResetTimeButton: View {
    let session: PresentationSession

    var body: some View {
        Button("Reset Time", systemImage: "arrow.counterclockwise") {
            session.timer.reset()
        }
    }
}
