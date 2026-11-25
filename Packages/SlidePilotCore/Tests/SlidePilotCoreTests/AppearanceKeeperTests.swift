import SlidePilotCore
import Testing

@MainActor
private final class FakeApplier: AppearanceApplying {
    var applied: [AppAppearance] = []
    func apply(_ appearance: AppAppearance) { applied.append(appearance) }
}

@MainActor
@Suite
struct AppearanceKeeperTests {
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    // SET-05: the stored appearance applies from launch on.
    @Test func appliesTheStoredAppearanceAtOnce() {
        let applier = FakeApplier()
        let settings = AppSettings(store: InMemorySettingsStore(values: ["appearance": "light"]))
        let keeper = AppearanceKeeper(settings: settings, applier: applier)
        #expect(applier.applied.first == .light)
        withExtendedLifetime(keeper) {}
    }

    // SET-05: changing the picker switches the windows without a relaunch.
    @Test func followsTheSetting() async {
        let applier = FakeApplier()
        let settings = AppSettings(store: InMemorySettingsStore())
        let keeper = AppearanceKeeper(settings: settings, applier: applier)
        #expect(applier.applied.last == .system)

        settings.appearance = .dark
        await settle { applier.applied.last == .dark }
        #expect(applier.applied.last == .dark)

        settings.appearance = .system
        await settle { applier.applied.last == .system }
        #expect(applier.applied.last == .system)
        withExtendedLifetime(keeper) {}
    }

    // A released keeper stops following the setting.
    @Test func stopsWhenTheKeeperGoes() async {
        let applier = FakeApplier()
        let settings = AppSettings(store: InMemorySettingsStore())
        var keeper: AppearanceKeeper? = AppearanceKeeper(settings: settings, applier: applier)
        await settle { applier.applied.count >= 2 }
        withExtendedLifetime(keeper) {}
        keeper = nil
        let count = applier.applied.count

        settings.appearance = .dark
        for _ in 0..<50 { await Task.yield() }
        #expect(applier.applied.count == count)
    }
}
