import SlidePilotCore
import SwiftUI

/// The stopwatch/timer and the clock at the top of the presenter (TIME-01 to TIME-03,
/// TIME-06). Plain system text with monospaced digits instead of the old custom time view
/// (ADR 0010).
struct TimeDisplay: View {
    let timer: PresentationTimer
    let size: TimeDisplaySize

    // TIME-06: the old app's 70 pt (normal) and 55 pt (small) presenter time, readable from a
    // step away. Scaled with Dynamic Type relative to the largest text style.
    @ScaledMetric(relativeTo: .largeTitle) private var normalFontSize: CGFloat = 70
    @ScaledMetric(relativeTo: .largeTitle) private var smallFontSize: CGFloat = 55

    var body: some View {
        // Like the old app: two equal halves, the timer centered in the left one and the
        // clock in the right one, so neither moves when the other's width changes.
        HStack(spacing: 0) {
            timerValue.frame(maxWidth: .infinity)
            clock.frame(maxWidth: .infinity)
        }
        .font(.system(size: size == .small ? smallFontSize : normalFontSize, weight: .light))
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
                TimerValueText(timer: timer, now: context.date)
            }
        } else {
            // Stopped: the value does not depend on the time.
            TimerValueText(timer: timer, now: .now)
        }
    }
}

/// The stopwatch or timer value, `- HH:MM:SS` in system red in overtime (TIME-03).
private struct TimerValueText: View {
    let timer: PresentationTimer
    let now: Date

    var body: some View {
        let seconds = timer.displayedSeconds(at: now)
        let isOvertime = timer.isOvertime(at: now)
        Text(verbatim: TimerValueFormat.string(seconds: seconds))
            .foregroundStyle(isOvertime ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .accessibilityLabel(timer.mode == .stopwatch ? Text("Stopwatch") : Text("Timer"))
            .accessibilityValue(accessibilityValue(seconds: seconds, isOvertime: isOvertime))
    }

    /// Spoken as words ("1 minute, 5 seconds"), not as digits with colons.
    private func accessibilityValue(seconds: Int, isOvertime: Bool) -> String {
        let duration = Duration.seconds(abs(seconds))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        let value = isOvertime ? String(localized: "Overtime \(duration)") : duration
        return timer.isRunning ? value : String(localized: "\(value), stopped")
    }
}
