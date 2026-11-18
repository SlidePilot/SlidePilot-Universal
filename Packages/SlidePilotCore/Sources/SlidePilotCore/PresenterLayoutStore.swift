import Foundation
import Observation

/// Where the presenter layout is kept between launches (LAY-05).
///
/// This store keeps the global "last used" layout. The per-document layout lives in the
/// companion file (`DocumentSettings.layout`); a document without one opens with this one.
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
/// layout, so the next document opens with it, and reported to `onChange`, which saves it
/// for this document (LAY-05).
@MainActor
@Observable
public final class PresenterLayoutModel {
    public private(set) var layout: PresenterLayout {
        didSet {
            if layout != oldValue, !isApplyingStoredLayout {
                store.saveLastUsedLayout(layout)
                onChange?(layout)
            }
        }
    }

    /// Called after every change by the user, not for `applyStoredLayout(_:)`.
    @ObservationIgnored public var onChange: ((PresenterLayout) -> Void)?
    @ObservationIgnored private let store: any PresenterLayoutStore
    @ObservationIgnored private var isApplyingStoredLayout = false

    public init(store: any PresenterLayoutStore) {
        self.store = store
        layout = store.lastUsedLayout() ?? .default
    }

    /// Shows the layout saved for this document when it opens (LAY-05). Loading is not a
    /// change, so the last-used layout stays as it is.
    public func applyStoredLayout(_ stored: PresenterLayout) {
        isApplyingStoredLayout = true
        layout = stored
        isApplyingStoredLayout = false
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

    /// Shows `slot` at `position`, swapping it with the slot there (LAY-04).
    public func setSlot(_ slot: PresenterSlot, at position: Int) {
        layout.setSlot(slot, at: position)
    }

    public func leadingFraction(in arrangement: PresenterArrangement) -> Double {
        layout.leadingFraction(in: arrangement)
    }

    public func setLeadingFraction(_ fraction: Double, in arrangement: PresenterArrangement) {
        layout.setLeadingFraction(fraction, in: arrangement)
    }
}
