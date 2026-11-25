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

    // Release check (#41): a long day of teaching with breaks, and a timer far into
    // overtime, still shows the exact time (docs/performance.md).
    @Test func longPresentationWithBreaksStaysExact() {
        var timer = PresentationTimer()
        var now: TimeInterval = 0
        var running: TimeInterval = 0
        // Eight 90-minute blocks with a 15.4-second remainder and breaks in between.
        for _ in 0..<8 {
            timer.toggle(at: at(now))
            now += 5_415.4
            running += 5_415.4
            timer.toggle(at: at(now))
            now += 900.3
        }
        #expect(timer.displayedSeconds(at: at(now)) == Int(running))

        var countdown = PresentationTimer()
        countdown.setTimer(seconds: 45 * 60)
        countdown.toggle(at: at(0))
        #expect(countdown.displayedSeconds(at: at(10 * 3_600)) == 45 * 60 - 10 * 3_600)
        #expect(countdown.isOvertime(at: at(10 * 3_600)))
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
        timer.setTimer(seconds: 90)
        #expect(timer.mode == .timer)
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
        var timer = PresentationTimer()
        timer.setTimer(seconds: 300)
        timer.toggle(at: at(0))
        timer.reset()
        #expect(timer.mode == .timer)
        #expect(timer.displayedSeconds(at: at(100)) == 300)
    }

    // TIME-04 (changed): setting a time switches a running stopwatch to a stopped timer.
    @Test func settingTimerSwitchesFromStopwatch() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.setTimer(seconds: 120)
        #expect(timer.mode == .timer)
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(50)) == 120)
    }

    // TIME-03: setting the time while the timer is on stops it and shows the new time.
    @Test func changingTimerStopsAndShowsNewTime() {
        var timer = PresentationTimer()
        timer.setTimer(seconds: 300)
        timer.toggle(at: at(0))
        timer.setTimer(seconds: 600)
        #expect(timer.mode == .timer)
        #expect(!timer.isRunning)
        #expect(timer.timerDuration == 600)
        #expect(timer.displayedSeconds(at: at(100)) == 600)
    }

    // TIME-04 (changed): setting zero turns the timer off.
    @Test func settingZeroTurnsTimerOff() {
        var timer = PresentationTimer()
        timer.setTimer(seconds: 300)
        timer.toggle(at: at(0))
        timer.setTimer(seconds: 0)
        #expect(timer.mode == .stopwatch)
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(10)) == 0)
        #expect(timer.timerDuration == 300)
    }

    // Setting zero or less in stopwatch mode changes nothing, a running stopwatch keeps running.
    @Test func settingZeroInStopwatchModeChangesNothing() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.setTimer(seconds: -5)
        #expect(timer.mode == .stopwatch)
        #expect(timer.isRunning)
        #expect(timer.timerDuration == 0)
        #expect(timer.displayedSeconds(at: at(10)) == 10)
    }

    // TIME-04 (changed): turning the timer off stops and goes back to the stopwatch at zero.
    @Test func turningTimerOffStopsAndResets() {
        var timer = PresentationTimer()
        timer.setTimer(seconds: 300)
        timer.toggle(at: at(0))
        timer.turnOffTimer()
        #expect(timer.mode == .stopwatch)
        #expect(!timer.isRunning)
        #expect(timer.displayedSeconds(at: at(50)) == 0)
    }

    @Test func turningTimerOffInStopwatchModeChangesNothing() {
        var timer = PresentationTimer()
        timer.toggle(at: at(0))
        timer.turnOffTimer()
        #expect(timer.isRunning)
        #expect(timer.displayedSeconds(at: at(10)) == 10)
    }

    // DEF-08: the old app cleared the set timer value when the mode changed. The set time
    // is kept, so Set Timer offers it again.
    @Test func turningTimerOffKeepsDuration() {
        var timer = PresentationTimer()
        timer.setTimer(seconds: 300)
        timer.turnOffTimer()
        #expect(timer.timerDuration == 300)
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
        timer.setTimer(seconds: 60)
        timer.turnOffTimer()
        timer.setTimer(seconds: 60)
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

@Suite
struct TimerStageTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let thresholds = TimerWarningThresholds(firstMinutes: 5, secondMinutes: 1)

    // TIME-08: a warning starts when the remaining time reaches its threshold and lasts
    // through zero; past zero is overtime.
    @Test func stagesByRemainingTime() {
        #expect(thresholds.stage(remainingSeconds: 301) == .normal)
        #expect(thresholds.stage(remainingSeconds: 300) == .firstWarning)
        #expect(thresholds.stage(remainingSeconds: 61) == .firstWarning)
        #expect(thresholds.stage(remainingSeconds: 60) == .secondWarning)
        #expect(thresholds.stage(remainingSeconds: 0) == .secondWarning)
        #expect(thresholds.stage(remainingSeconds: -1) == .overtime)
    }

    @Test func thresholdsCanBeOff() {
        let firstOff = TimerWarningThresholds(firstMinutes: 0, secondMinutes: 1)
        #expect(firstOff.stage(remainingSeconds: 120) == .normal)
        #expect(firstOff.stage(remainingSeconds: 60) == .secondWarning)
        let bothOff = TimerWarningThresholds(firstMinutes: 0, secondMinutes: 0)
        #expect(bothOff.stage(remainingSeconds: 0) == .normal)
        #expect(bothOff.stage(remainingSeconds: -1) == .overtime)
    }

    // A second threshold at or above the first takes over where both apply.
    @Test func secondWinsWhenNotBelowFirst() {
        let swapped = TimerWarningThresholds(firstMinutes: 2, secondMinutes: 5)
        #expect(swapped.stage(remainingSeconds: 300) == .secondWarning)
        #expect(swapped.stage(remainingSeconds: 60) == .secondWarning)
        #expect(swapped.stage(remainingSeconds: 301) == .normal)
    }

    // A timer set below a threshold starts in that stage, also while stopped.
    @Test func timerStageFollowsTheDisplayedValue() {
        var timer = PresentationTimer()
        timer.setTimer(seconds: 360)
        #expect(timer.stage(at: start, thresholds: thresholds) == .normal)
        timer.toggle(at: start)
        #expect(timer.stage(at: start.addingTimeInterval(60), thresholds: thresholds) == .firstWarning)
        #expect(timer.stage(at: start.addingTimeInterval(300), thresholds: thresholds) == .secondWarning)
        #expect(timer.stage(at: start.addingTimeInterval(361), thresholds: thresholds) == .overtime)
        timer.setTimer(seconds: 30)
        #expect(timer.stage(at: start, thresholds: thresholds) == .secondWarning)
    }

    // The stopwatch has no end, so it never warns.
    @Test func stopwatchStaysNormal() {
        var timer = PresentationTimer()
        timer.toggle(at: start)
        #expect(timer.stage(at: start.addingTimeInterval(10_000), thresholds: thresholds) == .normal)
    }

    @Test func defaultsAndChoices() {
        #expect(TimerWarningThresholds.default == TimerWarningThresholds(firstMinutes: 5, secondMinutes: 1))
        #expect(TimerWarningThresholds.choices.first == 0)
        #expect(TimerWarningThresholds.choices.contains(5))
        #expect(TimerWarningThresholds.choices.contains(1))
    }
}
