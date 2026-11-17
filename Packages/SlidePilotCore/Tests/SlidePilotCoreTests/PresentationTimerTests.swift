import Foundation
import SlidePilotCore
import Testing

@Suite
struct PresentationTimerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // TIME-04: the app starts in stopwatch mode.
    @Test func startsStoppedInStopwatchModeAtZero() {
        let timer = PresentationTimer()
        #expect(timer.mode == .stopwatch)
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(100)) == 0)
        #expect(timer.tickAnchor == nil)
    }

    // TIME-02: counts up in whole seconds once a full second has passed.
    @Test func stopwatchCountsUp() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        #expect(timer.isRunning)
        #expect(timer.displayedSeconds(at: at(0.999)) == 0)
        #expect(timer.displayedSeconds(at: at(1)) == 1)
        #expect(timer.displayedSeconds(at: at(3_725.4)) == 3_725)
    }

    // TIME-07: the value comes from the elapsed wall-clock time, not from counted ticks,
    // so a run of one hour shows exactly one hour (DEF-08).
    @Test func doesNotDrift() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        #expect(timer.displayedSeconds(at: at(3_600)) == 3_600)
    }

    @Test func stopKeepsValueAndStartContinues() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.toggle(at: at(10.6))
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(500)) == 10)
        timer.toggle(at: at(500))
        #expect(timer.displayedSeconds(at: at(500.3)) == 10)
        #expect(timer.displayedSeconds(at: at(500.4)) == 11)
    }

    // The display refreshes every second from the anchor, exactly when the value changes,
    // also after a pause with a fractional second.
    @Test func tickAnchorAlignsWithValueChanges() throws {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.toggle(at: at(10.6))
        timer.toggle(at: at(500))
        let anchor = try #require(timer.tickAnchor)
        #expect(anchor == at(500 - 10.6))
        #expect(timer.displayedSeconds(at: anchor.addingTimeInterval(11)) == 11)
        #expect(timer.displayedSeconds(at: anchor.addingTimeInterval(10.99)) == 10)
    }

    @Test func resetStopsAndGoesToZero() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.reset()
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(50)) == 0)
    }

    // TIME-03: the timer counts down from the set time and goes negative.
    @Test func timerCountsDownIntoOvertime() {
        var timer = PresentationTimer()
        timer.setMode(.timer)
        timer.setTimerDuration(90)
        #expect(timer.displayedSeconds(at: at(0)) == 90)
        timer.toggle(at: at(0))
        #expect(timer.displayedSeconds(at: at(0.5)) == 90)
        #expect(timer.displayedSeconds(at: at(1)) == 89)
        #expect(timer.displayedSeconds(at: at(90)) == 0)
        #expect(!timer.isOvertime(at: at(90)))
        #expect(timer.displayedSeconds(at: at(91)) == -1)
        #expect(timer.isOvertime(at: at(91)))
    }

    // TIME-03: Reset goes back to the set time.
    @Test func timerResetGoesBackToSetTime() {
        var timer = PresentationTimer(mode: .timer)
        timer.setTimerDuration(300)
        timer.toggle(at: at(0))
        timer.reset()
        #expect(timer.displayedSeconds(at: at(100)) == 300)
    }

    // TIME-03: setting the time stops the timer and shows the new time.
    @Test func setTimerStopsAndShowsNewTime() {
        var timer = PresentationTimer(mode: .timer)
        timer.setTimerDuration(300)
        timer.toggle(at: at(0))
        timer.setTimerDuration(600)
        #expect(!timer.isRunning)
        #expect(timer.timerDuration == 600)
        #expect(timer.displayedSeconds(at: at(100)) == 600)
    }

    // TIME-03: Set Timer is only available in timer mode.
    @Test func setTimerIsIgnoredInStopwatchMode() {
        var timer = PresentationTimer()
        timer.setTimerDuration(300)
        #expect(timer.timerDuration == 0)
    }

    @Test func negativeDurationCountsAsZero() {
        var timer = PresentationTimer(mode: .timer)
        timer.setTimerDuration(-5)
        #expect(timer.timerDuration == 0)
    }

    // TIME-04: switching the mode stops and resets the time.
    @Test func switchingModeStopsAndResets() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.setMode(.timer)
        #expect(timer.mode == .timer)
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(50)) == 0)
    }

    // DEF-08: the old app cleared the set timer value when the mode changed.
    @Test func switchingModeKeepsTimerDuration() {
        var timer = PresentationTimer(mode: .timer)
        timer.setTimerDuration(300)
        timer.setMode(.stopwatch)
        timer.setMode(.timer)
        #expect(timer.timerDuration == 300)
        #expect(timer.displayedSeconds(at: at(0)) == 300)
    }

    // Like the old app, choosing the current mode again also stops and resets.
    @Test func choosingTheSameModeResets() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.setMode(.stopwatch)
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(10)) == 0)
    }

    // TIME-05, NAV-09: the first "next slide" starts the time, later ones do nothing.
    @Test func firstNextSlideStartsTime() {
        var timer = PresentationTimer()
        #expect(timer.startsOnNextSlide)
        timer.nextSlideCommandWasUsed(at: at(0))
        #expect(timer.isRunning)
        #expect(!timer.startsOnNextSlide)
        timer.toggle(at: at(5))
        timer.nextSlideCommandWasUsed(at: at(6))
        #expect(!timer.isRunning)
    }

    // TIME-05: pressing Start/Stop manually turns the auto-start off.
    @Test func manualStartStopDisablesAutoStart() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.toggle(at: at(1))
        #expect(!timer.startsOnNextSlide)
        timer.nextSlideCommandWasUsed(at: at(2))
        #expect(!timer.isRunning)
    }

    // Like the old app, reset and mode changes do not turn the auto-start back on or off.
    @Test func resetAndModeChangeKeepAutoStart() {
        var timer = PresentationTimer()
        timer.reset()
        timer.setMode(.timer)
        #expect(timer.startsOnNextSlide)
        timer.nextSlideCommandWasUsed(at: at(0))
        #expect(timer.isRunning)
    }
}

@Suite
struct TimerValueFormatTests {
    @Test func formatsLikeTheOldApp() {
        #expect(TimerValueFormat.string(seconds: 0) == "00:00:00")
        #expect(TimerValueFormat.string(seconds: 59) == "00:00:59")
        #expect(TimerValueFormat.string(seconds: 3_725) == "01:02:05")
        #expect(TimerValueFormat.string(seconds: 100 * 3600) == "100:00:00")
    }

    @Test func formatsOvertimeWithMinus() {
        #expect(TimerValueFormat.string(seconds: -1) == "- 00:00:01")
        #expect(TimerValueFormat.string(seconds: -3_725) == "- 01:02:05")
    }
}

@Suite
struct TimerDurationComponentsTests {
    @Test func splitsAndJoins() {
        let components = TimerDurationComponents(totalSeconds: 3_725)
        #expect(components == TimerDurationComponents(hours: 1, minutes: 2, seconds: 5))
        #expect(components.totalSeconds == 3_725)
    }

    @Test func clampsFieldsToTheirRange() {
        #expect(TimerDurationComponents(hours: 30, minutes: 75, seconds: -4).totalSeconds == 23 * 3600 + 59 * 60)
        #expect(TimerDurationComponents(totalSeconds: 100 * 3600) == TimerDurationComponents(hours: 23, minutes: 59, seconds: 59))
        #expect(TimerDurationComponents(totalSeconds: -10).totalSeconds == 0)
    }
}

@Suite
struct TimeDisplaySizeTests {
    // TIME-06: same key and values as the old app; normal is the default.
    @Test func matchesOldDefaults() {
        #expect(TimeDisplaySize.defaultsKey == "timeSize")
        #expect(TimeDisplaySize(rawValue: 0) == .hidden)
        #expect(TimeDisplaySize(rawValue: 1) == .small)
        #expect(TimeDisplaySize(rawValue: 2) == .normal)
        #expect(TimeDisplaySize.default == .normal)
    }
}
