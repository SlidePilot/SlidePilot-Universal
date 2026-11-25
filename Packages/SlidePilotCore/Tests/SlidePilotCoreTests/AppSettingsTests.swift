import Foundation
import SlidePilotCore
import Testing

@MainActor
@Suite
struct AppSettingsTests {
    // SET-04, LAY-07: both settings are off without a stored value, like the old app.
    @Test func defaultsAreOff() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(!settings.keepsDisplayAwake)
        #expect(!settings.crossfadesSlides)
        #expect(!settings.savesDrawings)
    }

    // The old app's keys keep their meaning.
    @Test func usesTheOldKeys() {
        #expect(AppSettings.Key.keepsDisplayAwake == "isSleepDisabled")
        #expect(AppSettings.Key.crossfadesSlides == "crossfadeSlides")
        #expect(AppSettings.Key.savesDrawings == "saveDrawings")
    }

    @Test func readsStoredValues() {
        let store = InMemorySettingsStore(values: ["isSleepDisabled": true, "crossfadeSlides": true])
        let settings = AppSettings(store: store)
        #expect(settings.keepsDisplayAwake)
        #expect(settings.crossfadesSlides)
    }

    @Test func changesAreWrittenRightAway() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        settings.keepsDisplayAwake = true
        #expect(store.values["isSleepDisabled"] as? Bool == true)
        #expect(store.values["crossfadeSlides"] == nil)

        settings.crossfadesSlides = true
        settings.keepsDisplayAwake = false
        #expect(store.values["isSleepDisabled"] as? Bool == false)
        #expect(store.values["crossfadeSlides"] as? Bool == true)

        let reloaded = AppSettings(store: store)
        #expect(!reloaded.keepsDisplayAwake)
        #expect(reloaded.crossfadesSlides)
    }

    // A value of the wrong type (e.g. written by hand) falls back to the default.
    @Test func ignoresValuesOfTheWrongType() {
        let store = InMemorySettingsStore(values: ["isSleepDisabled": "yes"])
        #expect(!AppSettings(store: store).keepsDisplayAwake)
    }

    // REM-02: reachable by default, like the old app.
    @Test func remoteControlIsAllowedByDefault() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        #expect(settings.allowsRemoteControl)
        settings.allowsRemoteControl = false
        #expect(store.values["allowsRemoteControl"] as? Bool == false)
        #expect(!AppSettings(store: store).allowsRemoteControl)
    }

    // LAY-04, TIME-06: padding 30 pt and normal time size by default, the old keys and values.
    @Test func layoutDefaultsAndOldValues() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        #expect(settings.layoutPadding == .normal)
        #expect(settings.timeDisplaySize == .normal)
        #expect(AppSettings.Key.layoutPadding == "layoutPadding")
        #expect(AppSettings.Key.timeDisplaySize == "timeSize")

        settings.layoutPadding = .small
        settings.timeDisplaySize = .hidden
        #expect(store.values["layoutPadding"] as? Int == 15)
        #expect(store.values["timeSize"] as? Int == 0)

        let reloaded = AppSettings(store: store)
        #expect(reloaded.layoutPadding == .small)
        #expect(reloaded.timeDisplaySize == .hidden)
    }

    // An unknown stored value (e.g. 20 pt) falls back to the default, like the old app.
    @Test func unknownLayoutValuesFallBack() {
        let store = InMemorySettingsStore(values: ["layoutPadding": 20, "timeSize": 7])
        let settings = AppSettings(store: store)
        #expect(settings.layoutPadding == .normal)
        #expect(settings.timeDisplaySize == .normal)
    }

    // REM-07: remote mode remembers its layout and progress display.
    @Test func remoteControlSettings() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        #expect(settings.remoteControlLayout == .currentAndNext)
        #expect(settings.remoteShowsProgress)
        #expect(settings.remoteLastDeviceID == nil)
        settings.remoteControlLayout = .currentAndNotes
        settings.remoteShowsProgress = false
        settings.remoteLastDeviceID = "device"
        let reloaded = AppSettings(store: store)
        #expect(reloaded.remoteControlLayout == .currentAndNotes)
        #expect(!reloaded.remoteShowsProgress)
        #expect(reloaded.remoteLastDeviceID == "device")
        let unknown = AppSettings(store: InMemorySettingsStore(values: ["remoteControlLayout": "grid"]))
        #expect(unknown.remoteControlLayout == .currentAndNext)
    }

    @Test func layoutPaddingPoints() {
        #expect(LayoutPadding.allCases.map(\.points) == [0, 15, 30])
    }

    @Test func userDefaultsRoundTrip() throws {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(store: defaults)
        #expect(!settings.crossfadesSlides)
        settings.crossfadesSlides = true
        #expect(defaults.bool(forKey: "crossfadeSlides"))
        #expect(AppSettings(store: defaults).crossfadesSlides)
    }

    // TIME-08: 5 and 1 minutes by default; changes are stored and read back.
    @Test func timerWarnings() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        #expect(settings.timerWarnings == .default)
        settings.timerWarnings = TimerWarningThresholds(firstMinutes: 10, secondMinutes: 0)
        #expect(store.values[AppSettings.Key.timerFirstWarningMinutes] as? Int == 10)
        #expect(store.values[AppSettings.Key.timerSecondWarningMinutes] as? Int == 0)
        #expect(AppSettings(store: store).timerWarnings == TimerWarningThresholds(firstMinutes: 10, secondMinutes: 0))
    }

    // Values the settings do not offer fall back to the default.
    @Test func unknownTimerWarningsFallBack() {
        let store = InMemorySettingsStore(values: [
            AppSettings.Key.timerFirstWarningMinutes: 7,
            AppSettings.Key.timerSecondWarningMinutes: "1",
        ])
        #expect(AppSettings(store: store).timerWarnings == .default)
    }

    // DRAW-06: "Save drawings" is read from and written to the old key.
    @Test func savesDrawingsUsesTheOldKey() {
        let store = InMemorySettingsStore(values: ["saveDrawings": true])
        let settings = AppSettings(store: store)
        #expect(settings.savesDrawings)
        settings.savesDrawings = false
        #expect(store.values["saveDrawings"] as? Bool == false)
    }
}

@MainActor
@Suite
struct IndividualPointerSettingTests {
    // PTR-05: the custom pointer is Target until the user edits it.
    @Test func defaultsToTarget() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(settings.individualPointer == .target)
        #expect(AppSettings.Key.individualPointer == "individualPointerKey")
    }

    @Test func storesTheEditedPointer() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        let pointer = PointerConfiguration(
            shape: .plus, size: 30, thickness: 6, color: PointerColor(red: 0, green: 0.5, blue: 1, alpha: 0.8),
            borderWidth: 2, borderColor: .white, shadowWidth: 4
        )
        settings.individualPointer = pointer
        #expect(store.values["individualPointerKey"] is Data)
        #expect(AppSettings(store: store).individualPointer == pointer)
    }

    // The old app's value (colors as archived NSColor) or anything else unreadable falls
    // back to the default.
    @Test func ignoresUnreadableValues() {
        let old = Data(#"{"shape":0,"size":44,"color":"YnBsaXN0"}"#.utf8)
        #expect(AppSettings(store: InMemorySettingsStore(values: ["individualPointerKey": old])).individualPointer == .target)
        #expect(AppSettings(store: InMemorySettingsStore(values: ["individualPointerKey": "target"])).individualPointer == .target)
    }

    @Test func clampsStoredValues() throws {
        let stored = try JSONEncoder().encode(PointerConfiguration(shape: .target, size: 500, thickness: 3))
        let settings = AppSettings(store: InMemorySettingsStore(values: ["individualPointerKey": stored]))
        #expect(settings.individualPointer.size == 150)
    }
}
