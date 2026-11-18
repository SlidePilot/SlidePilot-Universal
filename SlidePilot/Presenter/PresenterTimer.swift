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
    // TIME-06: global, the layout editor and settings of later issues change it.
    @AppStorage(TimeDisplaySize.defaultsKey) private var size = TimeDisplaySize.default

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if size != .hidden {
                    TimeDisplay(timer: session.timer, size: size)
                        // Aligned with the slides' 30 pt padding; the old app's top margin.
                        .padding(.horizontal, 30)
                        .padding(.top, size == .small ? 5 : 20)
                }
            }
    }
}

private struct PresenterTimerModifier: ViewModifier {
    let session: PresentationSession
    @State private var isSettingTimer = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                TimerToolbar(session: session, isSettingTimer: $isSettingTimer)
            }
            .sheet(isPresented: $isSettingTimer) {
                SetTimerSheet(duration: session.timer.timerDuration) { seconds in
                    session.timer.setTimerDuration(seconds)
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

/// Mode, Set Timer, Start/Stop and Reset in the presenter's toolbar (TIME-02 to TIME-04).
private struct TimerToolbar: ToolbarContent {
    let session: PresentationSession
    @Binding var isSettingTimer: Bool

    var body: some ToolbarContent {
        ToolbarItem {
            TimeModePicker(session: session)
                .pickerStyle(.segmented)
                // Only as wide as its labels; the iPad toolbar would stretch it.
                .fixedSize()
        }
        ToolbarItemGroup {
            Button("Set Timer…", systemImage: "timer") {
                isSettingTimer = true
            }
            .disabled(session.timer.mode != .timer)
            StartStopTimeButton(session: session)
            ResetTimeButton(session: session)
        }
    }
}

/// Stopwatch / Timer (TIME-04). Used in the toolbar and the Moderator menu.
struct TimeModePicker: View {
    let session: PresentationSession

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { session.timer.mode },
            set: { session.timer.setMode($0) }
        )) {
            Text("Stopwatch").tag(TimeMode.stopwatch)
            Text("Timer").tag(TimeMode.timer)
        }
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
