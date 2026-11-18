/// What covers the presentation instead of the slide (CUR-01). Black and white exclude
/// each other. Not persisted: every document opens without a curtain (CUR-03).
public enum Curtain: String, Sendable, Equatable, CaseIterable {
    case none, black, white

    public var isShown: Bool {
        self != .none
    }

    /// Shows `curtain`, or hides it when it is already shown. Showing one color replaces
    /// the other, like the old app's B and W keys.
    public mutating func toggle(_ curtain: Curtain) {
        self = self == curtain ? .none : curtain
    }

    /// Shows `curtain` or hides it, for a checkable menu item or toolbar button. Hiding a
    /// color that is not shown changes nothing.
    public mutating func set(_ curtain: Curtain, shown: Bool) {
        if shown {
            self = curtain
        } else if self == curtain {
            self = .none
        }
    }
}
