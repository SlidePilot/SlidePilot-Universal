import Foundation
import Observation

/// Where the presenter layout is kept between launches (LAY-05).
///
/// Phase 2 stores only the global "last used" layout. The per-document layout (#25) adds
/// its own lookup in front of it: a document without a saved layout opens with this one.
public protocol PresenterLayoutStore: AnyObject {
    /// The layout saved by the last change in any document, or `nil` before the first one.
    func lastUsedLayout() -> PresenterLayout?
    func saveLastUsedLayout(_ layout: PresenterLayout)
}

/// Keeps the last-used layout as JSON in `UserDefaults`.
public final class UserDefaultsPresenterLayoutStore: PresenterLayoutStore {
    /// A new key: the old app's `layoutConfiguration` has another format and lives in the
    /// old app's container.
    public static let key = "presenterLayout"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func lastUsedLayout() -> PresenterLayout? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PresenterLayout.self, from: data)
    }

    public func saveLastUsedLayout(_ layout: PresenterLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Keeps the layout in memory only; for tests and previews.
public final class InMemoryPresenterLayoutStore: PresenterLayoutStore {
    public private(set) var layout: PresenterLayout?

    public init(layout: PresenterLayout? = nil) {
        self.layout = layout
    }

    public func lastUsedLayout() -> PresenterLayout? {
        layout
    }

    public func saveLastUsedLayout(_ layout: PresenterLayout) {
        self.layout = layout
    }
}

/// The presenter layout of one document window. Every change is saved as the last-used
/// layout, so the next document opens with it (LAY-05).
@MainActor
@Observable
public final class PresenterLayoutModel {
    public private(set) var layout: PresenterLayout {
        didSet {
            if layout != oldValue {
                store.saveLastUsedLayout(layout)
            }
        }
    }

    @ObservationIgnored private let store: any PresenterLayoutStore

    public init(store: any PresenterLayoutStore) {
        self.store = store
        layout = store.lastUsedLayout() ?? .default
    }

    public var arrangement: PresenterArrangement { layout.arrangement }

    public func setArrangement(_ arrangement: PresenterArrangement) {
        layout.setArrangement(arrangement)
    }

    public func isVisible(_ slot: PresenterSlot) -> Bool {
        layout.isVisible(slot)
    }

    public func setVisible(_ slot: PresenterSlot, _ isVisible: Bool) {
        layout.setVisible(slot, isVisible)
    }

    public func toggle(_ slot: PresenterSlot) {
        layout.toggle(slot)
    }

    public func leadingFraction(in arrangement: PresenterArrangement) -> Double {
        layout.leadingFraction(in: arrangement)
    }

    public func setLeadingFraction(_ fraction: Double, in arrangement: PresenterArrangement) {
        layout.setLeadingFraction(fraction, in: arrangement)
    }
}
