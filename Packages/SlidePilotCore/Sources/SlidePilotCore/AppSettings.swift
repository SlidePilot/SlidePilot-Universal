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
/// One instance per app. Every change is written to the store right away.
@MainActor
@Observable
public final class AppSettings {
    /// The old app's `UserDefaults` keys, so the meaning stays the same.
    public enum Key {
        public static let keepsDisplayAwake = "isSleepDisabled"
        public static let crossfadesSlides = "crossfadeSlides"
        public static let allowsRemoteControl = "allowsRemoteControl"
        public static let savesDrawings = "saveDrawings"
        public static let layoutPadding = "layoutPadding"
        public static let timeDisplaySize = TimeDisplaySize.defaultsKey
        public static let remoteControlLayout = "remoteControlLayout"
        public static let remoteShowsProgress = "remoteShowsProgress"
        public static let remoteLastDeviceID = "remoteLastDeviceID"
        public static let individualPointer = "individualPointerKey"
        public static let appearance = "appearance"
    }

    /// Keep the display awake while the app runs (SET-04, SET-05). Default off.
    public var keepsDisplayAwake: Bool {
        didSet { store.set(keepsDisplayAwake, forKey: Key.keepsDisplayAwake) }
    }

    /// The look of the app's windows (SET-05). Default: follows the system.
    public var appearance: AppAppearance {
        didSet { store.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Crossfade between slides on the presentation window (LAY-07, SET-05). Default off.
    public var crossfadesSlides: Bool {
        didSet { store.set(crossfadesSlides, forKey: Key.crossfadesSlides) }
    }

    /// Keep drawings across slide changes and store them with the document (DRAW-06,
    /// DRAW-07). Default off. Turning it off deletes all drawings; the app does that.
    public var savesDrawings: Bool {
        didSet { store.set(savesDrawings, forKey: Key.savesDrawings) }
    }

    /// Other devices may find this one and control it once paired (REM-02). Default on, as
    /// the old app was always reachable.
    public var allowsRemoteControl: Bool {
        didSet { store.set(allowsRemoteControl, forKey: Key.allowsRemoteControl) }
    }

    /// Space around the presenter's slots (LAY-04). Default 30 pt.
    public var layoutPadding: LayoutPadding {
        didSet { store.set(layoutPadding.rawValue, forKey: Key.layoutPadding) }
    }

    /// Size of the clock and stopwatch/timer in the presenter (TIME-06). Default normal.
    public var timeDisplaySize: TimeDisplaySize {
        didSet { store.set(timeDisplaySize.rawValue, forKey: Key.timeDisplaySize) }
    }

    /// What remote mode shows of the controlled presentation (REM-07). Default: current and
    /// next slide.
    public var remoteControlLayout: RemoteControlLayout {
        didSet { store.set(remoteControlLayout.rawValue, forKey: Key.remoteControlLayout) }
    }

    /// Remote mode shows the presentation's progress (REM-07). Default on.
    public var remoteShowsProgress: Bool {
        didSet { store.set(remoteShowsProgress, forKey: Key.remoteShowsProgress) }
    }

    /// The device remote mode controlled last; a new remote mode window connects to it
    /// again when it is nearby and trusted (REM-07).
    public var remoteLastDeviceID: String? {
        didSet { store.set(remoteLastDeviceID, forKey: Key.remoteLastDeviceID) }
    }

    /// The custom pointer of the Individual appearance, edited in the pointer editor
    /// (PTR-04). Global, not per document (PTR-05, PTR-07); stored as JSON with sRGB colors.
    /// Default: Target.
    public var individualPointer: PointerConfiguration {
        didSet {
            guard individualPointer != oldValue else { return }
            store.set(try? JSONEncoder().encode(individualPointer), forKey: Key.individualPointer)
        }
    }

    @ObservationIgnored private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
        keepsDisplayAwake = store.object(forKey: Key.keepsDisplayAwake) as? Bool ?? false
        crossfadesSlides = store.object(forKey: Key.crossfadesSlides) as? Bool ?? false
        appearance = (store.object(forKey: Key.appearance) as? String)
            .flatMap(AppAppearance.init(rawValue:)) ?? .default
        savesDrawings = store.object(forKey: Key.savesDrawings) as? Bool ?? false
        allowsRemoteControl = store.object(forKey: Key.allowsRemoteControl) as? Bool ?? true
        layoutPadding = (store.object(forKey: Key.layoutPadding) as? Int)
            .flatMap(LayoutPadding.init(rawValue:)) ?? .default
        timeDisplaySize = (store.object(forKey: Key.timeDisplaySize) as? Int)
            .flatMap(TimeDisplaySize.init(rawValue:)) ?? .default
        remoteControlLayout = (store.object(forKey: Key.remoteControlLayout) as? String)
            .flatMap(RemoteControlLayout.init(rawValue:)) ?? .default
        remoteShowsProgress = store.object(forKey: Key.remoteShowsProgress) as? Bool ?? true
        remoteLastDeviceID = store.object(forKey: Key.remoteLastDeviceID) as? String
        individualPointer = (store.object(forKey: Key.individualPointer) as? Data)
            .flatMap { try? JSONDecoder().decode(PointerConfiguration.self, from: $0) }?
            .clampedForEditor() ?? .defaultIndividual
    }
}
