import SlidePilotCore
import Testing

@MainActor
private final class FakeBlocker: DisplaySleepBlocking {
    var isBlocking = false
}

@MainActor
@Suite
struct DisplayAwakeKeeperTests {
    /// Lets the keeper's observation task run until `condition` holds (or gives up).
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    // SET-04: off by default, so the display may sleep.
    @Test func doesNotBlockByDefault() {
        let blocker = FakeBlocker()
        let keeper = DisplayAwakeKeeper(settings: AppSettings(store: InMemorySettingsStore()), blocker: blocker)
        #expect(!blocker.isBlocking)
        withExtendedLifetime(keeper) {}
    }

    // SET-04: a stored setting keeps the display awake from launch on.
    @Test func blocksAtLaunchWhenStoredOn() {
        let blocker = FakeBlocker()
        let settings = AppSettings(store: InMemorySettingsStore(values: ["isSleepDisabled": true]))
        let keeper = DisplayAwakeKeeper(settings: settings, blocker: blocker)
        #expect(blocker.isBlocking)
        withExtendedLifetime(keeper) {}
    }

    // SET-04: turning the toggle on and off takes effect without a relaunch.
    @Test func followsTheSetting() async {
        let blocker = FakeBlocker()
        let settings = AppSettings(store: InMemorySettingsStore())
        let keeper = DisplayAwakeKeeper(settings: settings, blocker: blocker)

        settings.keepsDisplayAwake = true
        await settle { blocker.isBlocking }
        #expect(blocker.isBlocking)

        settings.keepsDisplayAwake = false
        await settle { !blocker.isBlocking }
        #expect(!blocker.isBlocking)
        withExtendedLifetime(keeper) {}
    }

    // The assertion is never leaked: releasing the keeper lets the display sleep again.
    @Test func releasesWhenTheKeeperGoes() {
        let blocker = FakeBlocker()
        let settings = AppSettings(store: InMemorySettingsStore(values: ["isSleepDisabled": true]))
        var keeper: DisplayAwakeKeeper? = DisplayAwakeKeeper(settings: settings, blocker: blocker)
        #expect(blocker.isBlocking)
        withExtendedLifetime(keeper) {}
        keeper = nil
        #expect(!blocker.isBlocking)
    }

    // LAY-07: only with the setting on and Reduce Motion off; 0.6 s like the old app.
    @Test(arguments: [(true, false, true), (true, true, false), (false, false, false), (false, true, false)])
    func crossfadeRespectsReduceMotion(setting: Bool, reduceMotion: Bool, expected: Bool) {
        #expect(SlideCrossfade.isActive(setting: setting, reduceMotion: reduceMotion) == expected)
        #expect(SlideCrossfade.duration == 0.6)
    }
}
