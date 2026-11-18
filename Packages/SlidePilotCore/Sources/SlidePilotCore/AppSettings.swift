import Foundation
import Observation

/// Where the app-wide settings are kept between launches (SET-01).
///
/// `UserDefaults` conforms as is; tests and previews use `InMemorySettingsStore`.
public protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

/// Keeps the settings in memory only; for tests and previews.
public final class InMemorySettingsStore: SettingsStore {
    public private(set) var values: [String: Any]

    public init(values: [String: Any] = [:]) {
        self.values = values
    }

    public func object(forKey key: String) -> Any? {
        values[key]
    }

    public func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}

/// The app-wide settings shown in the Settings window (Mac) and the settings sheet (iPad).
///
/// One instance per app. Every change is written to the store right away. Later issues add
/// their settings here (layout, pointer, remote).
@MainActor
@Observable
public final class AppSettings {
    /// The old app's `UserDefaults` keys, so the meaning stays the same.
    public enum Key {
        public static let keepsDisplayAwake = "isSleepDisabled"
        public static let crossfadesSlides = "crossfadeSlides"
        public static let allowsRemoteControl = "allowsRemoteControl"
    }

    /// Keep the display awake while the app runs (SET-04, SET-05). Default off.
    public var keepsDisplayAwake: Bool {
        didSet { store.set(keepsDisplayAwake, forKey: Key.keepsDisplayAwake) }
    }

    /// Crossfade between slides on the presentation window (LAY-07, SET-05). Default off.
    public var crossfadesSlides: Bool {
        didSet { store.set(crossfadesSlides, forKey: Key.crossfadesSlides) }
    }

    /// Other devices may find this one and control it once paired (REM-02). Default on, as
    /// the old app was always reachable.
    public var allowsRemoteControl: Bool {
        didSet { store.set(allowsRemoteControl, forKey: Key.allowsRemoteControl) }
    }

    @ObservationIgnored private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
        keepsDisplayAwake = store.object(forKey: Key.keepsDisplayAwake) as? Bool ?? false
        crossfadesSlides = store.object(forKey: Key.crossfadesSlides) as? Bool ?? false
        allowsRemoteControl = store.object(forKey: Key.allowsRemoteControl) as? Bool ?? true
    }
}
