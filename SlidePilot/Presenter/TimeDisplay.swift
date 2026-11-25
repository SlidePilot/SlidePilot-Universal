import SlidePilotCore
import SwiftUI

/// The stopwatch/timer and the clock at the top of the presenter (TIME-01 to TIME-03,
/// TIME-06). Plain system text with monospaced digits instead of the old custom time view
/// (ADR 0010).
struct TimeDisplay: View {
    let timer: PresentationTimer
    let size: TimeDisplaySize
    /// When the timer turns to its warning colors (TIME-08).
    var warnings = TimerWarningThresholds.default

    // TIME-06: the old app's 70 pt (normal) and 55 pt (small) presenter time, readable from a
    // step away. Scaled with Dynamic Type relative to the largest text style.
    @ScaledMetric(relativeTo: .largeTitle) private var normalFontSize: CGFloat = 70
    @ScaledMetric(relativeTo: .largeTitle) private var smallFontSize: CGFloat = 55
    @Environment(\.isCompactHeight) private var isCompactHeight

    private var fontSize: CGFloat {
        let size = size == .small ? smallFontSize : normalFontSize
        // In compact height (e.g. a phone in landscape) the full size would take about a
        // third of the screen from the slides.
        return isCompactHeight ? size / 2 : size
    }

    var body: some View {
        // Like the old app: two equal halves, the timer centered in the left one and the
        // clock in the right one, so neither moves when the other's width changes. The
        // padding keeps a gap between them when narrow windows shrink both to their halves.
        HStack(spacing: 0) {
            timerValue.padding(.horizontal).frame(maxWidth: .infinity)
            clock.padding(.horizontal).frame(maxWidth: .infinity)
        }
        .font(.system(size: fontSize, weight: .light))
        .monospacedDigit()
        .lineLimit(1)
        // Shrinks instead of truncating in narrow windows and at large text sizes.
        .minimumScaleFactor(0.3)
    }

    /// TIME-01: the wall clock with seconds in the user's locale (12 or 24 h, DEF-09).
    private var clock: some View {
        // Refreshes on every whole wall-clock second.
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { context in
            let time = Text(context.date, format: .dateTime.hour().minute().second())
            time
                .accessibilityLabel(Text("Clock"))
                .accessibilityValue(time)
        }
    }

    @ViewBuilder private var timerValue: some View {
        if let anchor = timer.tickAnchor {
            TimelineView(.periodic(from: anchor, by: 1)) { context in
                TimerValueText(timer: timer, warnings: warnings, now: context.date)
            }
        } else {
            // Stopped: the value does not depend on the time.
            TimerValueText(timer: timer, warnings: warnings, now: .now)
        }
    }
}

extension EnvironmentValues {
    /// Whether the window has a compact height, like a phone in landscape. Never on the Mac,
    /// which has no size classes.
    var isCompactHeight: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }
}

/// The stopwatch or timer value, `- HH:MM:SS` in system red in overtime (TIME-03), in the
/// warning colors as the timer's end comes closer (TIME-08).
private struct TimerValueText: View {
    let timer: PresentationTimer
    let warnings: TimerWarningThresholds
    let now: Date

    var body: some View {
        let seconds = timer.displayedSeconds(at: now)
        let stage = timer.stage(at: now, thresholds: warnings)
        Text(verbatim: TimerValueFormat.string(seconds: seconds))
            .foregroundStyle(stage.style)
            .accessibilityLabel(timer.mode == .stopwatch ? Text("Stopwatch") : Text("Timer"))
            .accessibilityValue(accessibilityValue(seconds: seconds, stage: stage))
    }

    /// Spoken as words ("1 minute, 5 seconds"), not as digits with colons. The warning
    /// stage is said too, so it is not shown by color alone.
    private func accessibilityValue(seconds: Int, stage: TimerStage) -> String {
        let duration = Duration.seconds(abs(seconds))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        let value = switch stage {
        case .normal: duration
        case .firstWarning: String(localized: "\(duration), first warning")
        case .secondWarning: String(localized: "\(duration), second warning")
        case .overtime: String(localized: "Overtime \(duration)")
        }
        return timer.isRunning ? value : String(localized: "\(value), stopped")
    }
}

private extension TimerStage {
    /// Orange, then purple, so the second warning stays apart from the overtime red. The
    /// orange is an asset color: system orange has too little contrast on a light background.
    var style: AnyShapeStyle {
        switch self {
        case .normal: AnyShapeStyle(.primary)
        case .firstWarning: AnyShapeStyle(Color(.timerFirstWarning))
        case .secondWarning: AnyShapeStyle(.purple)
        case .overtime: AnyShapeStyle(.red)
        }
    }
}
