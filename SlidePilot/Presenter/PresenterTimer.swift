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

    /// The Set Timer sheet and the menu commands. The toolbar's Time button opens the same
    /// sheet through `isSettingTimer` (`PresenterToolbar`).
    func presenterTimerControls(_ session: PresentationSession, isSettingTimer: Binding<Bool>) -> some View {
        modifier(PresenterTimerModifier(session: session, isSettingTimer: isSettingTimer))
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
                    TimeDisplay(timer: session.timer, size: size, warnings: settings?.timerWarnings ?? .default)
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
    @Binding var isSettingTimer: Bool

    func body(content: Content) -> some View {
        content
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

/// The Time button in the presenter's toolbar (TIME-02 to TIME-04; product-owner decision
/// 2026-11-25, #189): a click or tap starts or stops the time, its menu resets it and sets or
/// turns off the timer. The clock above the slides shows whether the timer is on.
struct TimeToolbarMenu: View {
    let session: PresentationSession
    @Binding var isSettingTimer: Bool
    /// In the overflow menu the system shows the menu as a submenu without its primary
    /// action, so Start/Stop becomes its first item and the submenu is called Time.
    var isInOverflow = false

    var body: some View {
        let isRunning = session.timer.isRunning
        Menu {
            if isInOverflow {
                Button(
                    isRunning ? "Stop Time" : "Start Time",
                    systemImage: isRunning ? "pause.fill" : "play.fill"
                ) {
                    session.timer.toggle()
                }
                Divider()
            }
            Button("Reset Time", systemImage: "arrow.counterclockwise") {
                session.timer.reset()
            }
            Divider()
            // Also changes a running timer without switching it off (TIME-04).
            Button("Set Timer…", systemImage: "timer") {
                isSettingTimer = true
            }
            Button("Turn Off Timer", systemImage: "stopwatch") {
                session.timer.turnOffTimer()
            }
            .disabled(session.timer.mode != .timer)
        } label: {
            if isInOverflow {
                Label("Time", systemImage: "stopwatch")
            } else {
                Label(
                    isRunning ? "Stop Time" : "Start Time",
                    systemImage: isRunning ? "pause.fill" : "play.fill"
                )
            }
        } primaryAction: {
            session.timer.toggle()
        }
        .help(isRunning ? Text("Stop Time") : Text("Start Time"))
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
