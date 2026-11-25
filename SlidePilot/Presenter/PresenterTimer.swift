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
            // text fields: the timer commands are off, and `isEditingText` turns off the
            // other plain-letter shortcuts (layout, navigator, draw).
            .focusedSceneValue(\.presenterTimer, isSettingTimer ? nil : FocusedPresenterTimer(
                session: session,
                showSetTimer: { isSettingTimer = true }
            ))
            .focusedSceneValue(\.isEditingText, isSettingTimer ? true : nil)
    }
}

/// The Time controls in the presenter's toolbar (TIME-02 to TIME-04; product-owner decision
/// 2026-11-25, #189): a click or tap starts or stops the time, a menu resets it and sets or
/// turns off the timer. The clock above the slides shows whether the timer is on.
///
/// - Mac: one split button, Start/Stop on the left, the menu behind the chevron.
/// - iPad: the same as two buttons, `TimeStartStopButton` and this menu with the chevron, since
///   a long press is hard to discover (same decision).
/// - Compact sizes (iPhone, a narrow iPad window): a plain Time menu with Start/Stop as its
///   first item, the same in the bar and in the overflow menu, which drops a primary action.
struct TimeToolbarMenu: View {
    enum Style {
        /// Start/Stop as the primary action (Mac).
        case split
        /// Only the menu, behind a chevron, next to `TimeStartStopButton` (iPad).
        case options
        /// A Time menu with Start/Stop as its first item (compact sizes).
        case compact
    }

    let session: PresentationSession
    @Binding var isSettingTimer: Bool
    let style: Style
    /// Optional, so snapshots and previews without settings leave out the timer warnings.
    @Environment(AppSettings.self) private var settings: AppSettings?

    var body: some View {
        let isRunning = session.timer.isRunning
        // Read here, not in the menu's content: the system builds the content outside the
        // body's observation, so a timer set later left Turn Off Timer disabled (iOS).
        let hasTimer = session.timer.mode == .timer
        let warnings = settings?.timerWarnings ?? .default
        Group {
            switch style {
            case .split:
                Menu {
                    items(isRunning: isRunning, hasTimer: hasTimer)
                } label: {
                    TimeStartStopButton.label(isRunning: isRunning)
                } primaryAction: {
                    session.timer.toggle()
                }
                .help(TimeStartStopButton.help(isRunning: isRunning))
            case .options:
                Menu {
                    items(isRunning: isRunning, hasTimer: hasTimer)
                } label: {
                    // The chevron of the Mac's split button; VoiceOver reads "Time".
                    Label("Time", systemImage: "chevron.down")
                }
                .help(Text("Time"))
            case .compact:
                Menu {
                    items(isRunning: isRunning, hasTimer: hasTimer)
                } label: {
                    Label("Time", systemImage: "stopwatch")
                }
            }
        }
        // The Mac builds the toolbar menu once and keeps the items' state; a new identity
        // rebuilds it when the timer is set or turned off or a warning changes.
        .id([hasTimer ? 1 : 0, warnings.firstMinutes, warnings.secondMinutes])
    }

    @ViewBuilder private func items(isRunning: Bool, hasTimer: Bool) -> some View {
        if style == .compact {
            Button {
                session.timer.toggle()
            } label: {
                TimeStartStopButton.label(isRunning: isRunning)
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
        .disabled(!hasTimer)
        if let settings {
            TimerWarningPickers(settings: settings)
        }
    }
}

/// Starts or stops the time (TIME-02), left of `TimeToolbarMenu` on the iPad.
struct TimeStartStopButton: View {
    let session: PresentationSession

    var body: some View {
        let isRunning = session.timer.isRunning
        Button {
            session.timer.toggle()
        } label: {
            Self.label(isRunning: isRunning)
        }
        .help(Self.help(isRunning: isRunning))
    }

    static func label(isRunning: Bool) -> Label<Text, Image> {
        Label(
            isRunning ? "Stop Time" : "Start Time",
            systemImage: isRunning ? "pause.fill" : "play.fill"
        )
    }

    static func help(isRunning: Bool) -> Text {
        isRunning ? Text("Stop Time") : Text("Start Time")
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
