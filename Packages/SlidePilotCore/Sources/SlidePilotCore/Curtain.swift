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

/// The curtain with the color its button shows (CUR-01, changed 2026-11-25): one button
/// shows and hides the curtain in the color shown last, black until white is chosen. Only
/// choosing the other color changes it; hiding the curtain keeps it.
public struct CurtainState: Sendable, Equatable {
    /// What covers the presentation now.
    public var shown: Curtain {
        didSet {
            if shown.isShown { color = shown }
        }
    }

    /// The color the button shows next: `.black` or `.white`, never `.none`.
    public private(set) var color: Curtain

    public init(shown: Curtain = .none) {
        self.shown = shown
        color = shown.isShown ? shown : .black
    }

    /// What one press of the curtain button shows: the remembered color, or no curtain
    /// while one is shown. The remote asks the host for it (REM-07).
    public var toggled: Curtain {
        shown.isShown ? .none : color
    }

    /// The curtain button: shows the remembered color or hides the curtain.
    public mutating func toggle() {
        shown = toggled
    }
}
