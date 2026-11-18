/// What a slot of the presenter layout shows (LAY-01).
public enum PresenterSlot: String, Codable, Sendable, CaseIterable {
    case current
    case next
    case notes
}

/// How the visible slots are arranged (LAY-01).
///
/// - `single`: slot 1 fills the window.
/// - `double`: slot 1 left, slot 2 right.
/// - `tripleLeft`: slot 3 large on the left, slots 1 and 2 stacked on the right.
/// - `tripleRight`: slots 1 and 2 stacked on the left, slot 3 large on the right.
public enum PresenterArrangement: String, Codable, Sendable, CaseIterable {
    case single
    case double
    case tripleLeft
    case tripleRight

    public var slotCount: Int {
        switch self {
        case .single: 1
        case .double: 2
        case .tripleLeft, .tripleRight: 3
        }
    }

    /// Whether a separator splits the window into a leading and a trailing column (LAY-03).
    public var hasSeparator: Bool { self != .single }

    /// The share of the width the leading column gets before the separator is moved.
    /// The large slot gets 60 %, like the old app's double layout.
    var defaultLeadingFraction: Double {
        switch self {
        case .single, .double, .tripleLeft: 0.6
        case .tripleRight: 0.4
        }
    }
}

/// The presenter layout: arrangement, slot order and separator positions (LAY-01 to LAY-03).
///
/// `slots` always holds every `PresenterSlot` once; the first `arrangement.slotCount` are
/// visible, the rest are hidden. Hiding and showing a slot follows the old app's
/// `LayoutConfiguration.hideSlide` / `showSlide`, including the remembered triple arrangement
/// and slot position (LAY-02).
public struct PresenterLayout: Sendable, Equatable {
    public private(set) var arrangement: PresenterArrangement
    public private(set) var slots: [PresenterSlot]
    /// The triple arrangement before a slot was hidden from it.
    private var previousTriple: PresenterArrangement?
    /// The slot index of the most recently hidden slot. Like the old app, only one is kept.
    private var previousPosition: [PresenterSlot: Int]
    /// The leading column's share of the width per arrangement (LAY-03).
    private var leadingFractions: [PresenterArrangement: Double]

    /// The old app's default: current slide and next slide side by side, notes hidden.
    public static let `default` = PresenterLayout(arrangement: .double)

    public init(arrangement: PresenterArrangement, slots: [PresenterSlot] = [.current, .next, .notes]) {
        self.arrangement = arrangement
        self.slots = Self.isValid(slots) ? slots : [.current, .next, .notes]
        previousTriple = nil
        previousPosition = [:]
        leadingFractions = [:]
    }

    /// The slots on screen, in slot order.
    public var visibleSlots: [PresenterSlot] {
        Array(slots.prefix(arrangement.slotCount))
    }

    public func isVisible(_ slot: PresenterSlot) -> Bool {
        visibleSlots.contains(slot)
    }

    /// Changes the arrangement and keeps the slot order (old `setLayoutConfigurationType`).
    public mutating func setArrangement(_ newArrangement: PresenterArrangement) {
        arrangement = newArrangement
    }

    /// Shows or hides `slot`. Showing a visible slot or hiding a hidden one does nothing;
    /// the old app could add a slot twice this way when notes were opened (AppDelegate:347).
    public mutating func setVisible(_ slot: PresenterSlot, _ isVisible: Bool) {
        guard isVisible != self.isVisible(slot) else { return }
        if isVisible {
            show(slot)
        } else {
            hide(slot)
        }
    }

    public mutating func toggle(_ slot: PresenterSlot) {
        setVisible(slot, !isVisible(slot))
    }

    /// Puts `slot` at `position` and the slot that was there where `slot` was, like dropping a
    /// slide symbol on a slot in the old layout editor (`moveSlide(_:to:swap: true)`). A slot
    /// that was hidden becomes visible and the replaced one hidden (LAY-04).
    public mutating func setSlot(_ slot: PresenterSlot, at position: Int) {
        guard slots.indices.contains(position) else { return }
        move(slot, to: position, swap: true)
    }

    /// The leading column's share of the width in `arrangement`, between 0 and 1.
    public func leadingFraction(in arrangement: PresenterArrangement) -> Double {
        leadingFractions[arrangement] ?? arrangement.defaultLeadingFraction
    }

    /// Stores the separator position of `arrangement`, clamped to 0…1.
    public mutating func setLeadingFraction(_ fraction: Double, in arrangement: PresenterArrangement) {
        guard fraction.isFinite, arrangement.hasSeparator else { return }
        leadingFractions[arrangement] = min(max(fraction, 0), 1)
    }

    // MARK: - Old hide/show logic (LayoutConfiguration.swift:72-156)

    private mutating func hide(_ slot: PresenterSlot) {
        guard let origin = slots.firstIndex(of: slot) else { return }
        previousPosition = [slot: origin]
        switch arrangement {
        case .tripleLeft:
            previousTriple = arrangement
            arrangement = .double
            moveToEnd(from: origin)
            // The stacked slots 1 and 2 are on the right in tripleLeft; swapping them keeps
            // the remaining slots on their side.
            slots.swapAt(0, 1)
        case .tripleRight:
            previousTriple = arrangement
            arrangement = .double
            moveToEnd(from: origin)
        case .double:
            arrangement = .single
            moveToEnd(from: origin)
        case .single:
            // The window is never empty: hiding the only slot shows the current slide instead,
            // and hiding the current slide when it is the only one does nothing.
            if slots.first != .current {
                moveToEnd(from: origin)
                move(.current, to: 0, swap: true)
            }
        }
    }

    private mutating func show(_ slot: PresenterSlot) {
        switch arrangement {
        case .single:
            arrangement = .double
            if let position = previousPosition[slot], position <= 1 {
                move(slot, to: position, swap: false)
            } else {
                move(slot, to: 1, swap: false)
            }
        case .double:
            arrangement = previousTriple ?? .tripleLeft
            if arrangement == .tripleLeft {
                slots.swapAt(0, 1)
            }
            if let position = previousPosition[slot], position <= 2 {
                move(slot, to: position, swap: false)
            } else {
                move(slot, to: 1, swap: false)
            }
        case .tripleLeft, .tripleRight:
            break
        }
    }

    private mutating func moveToEnd(from index: Int) {
        slots.append(slots.remove(at: index))
    }

    /// Moves `slot` to `target`, either by swapping with the slot there or by inserting it
    /// and shifting the others (old `moveSlide(_:to:swap:)`).
    private mutating func move(_ slot: PresenterSlot, to target: Int, swap: Bool) {
        guard let origin = slots.firstIndex(of: slot) else { return }
        if swap {
            slots.swapAt(origin, target)
        } else {
            slots.insert(slots.remove(at: origin), at: target)
        }
    }

    private static func isValid(_ slots: [PresenterSlot]) -> Bool {
        slots.count == PresenterSlot.allCases.count && Set(slots) == Set(PresenterSlot.allCases)
    }
}

extension PresenterLayout: Codable {
    private enum CodingKeys: String, CodingKey {
        case arrangement, slots, previousTriple, previousPosition, leadingFractions
    }

    /// Decodes leniently: a stored layout from a later version or a damaged one falls back
    /// to defaults per field instead of failing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let arrangement = (try? container.decode(PresenterArrangement.self, forKey: .arrangement)) ?? .double
        let slots = (try? container.decode([PresenterSlot].self, forKey: .slots)) ?? []
        self.init(arrangement: arrangement, slots: slots)
        let triple = try? container.decode(PresenterArrangement.self, forKey: .previousTriple)
        previousTriple = triple?.slotCount == 3 ? triple : nil
        let positions = (try? container.decode([PresenterSlot: Int].self, forKey: .previousPosition)) ?? [:]
        previousPosition = positions.filter { slots.indices.contains($0.value) }
        let fractions = (try? container.decode([PresenterArrangement: Double].self, forKey: .leadingFractions)) ?? [:]
        for (arrangement, fraction) in fractions {
            setLeadingFraction(fraction, in: arrangement)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arrangement, forKey: .arrangement)
        try container.encode(slots, forKey: .slots)
        try container.encodeIfPresent(previousTriple, forKey: .previousTriple)
        try container.encode(previousPosition, forKey: .previousPosition)
        try container.encode(leadingFractions, forKey: .leadingFractions)
    }
}

/// Separator limits of the presenter layout (LAY-03).
public enum PresenterSplit {
    /// Each column is at least this wide, like the old app's containers.
    public static let minimumColumnWidth: Double = 300

    /// Whether two columns fit side by side in `width` points.
    public static func fitsSideBySide(width: Double, separatorWidth: Double = 0) -> Bool {
        width - separatorWidth >= 2 * minimumColumnWidth
    }

    /// Whether the iPad stacks the columns vertically: when they do not fit side by side, or
    /// in a portrait window, where stacked slides are about twice as large. The stored
    /// layout stays unchanged.
    public static func stacksVertically(width: Double, height: Double, separatorWidth: Double = 0) -> Bool {
        !fitsSideBySide(width: width, separatorWidth: separatorWidth) || height > width
    }

    /// The leading column's width for `fraction` of `width`, keeping both columns at least
    /// `minimumColumnWidth` wide where possible.
    public static func leadingWidth(fraction: Double, width: Double, separatorWidth: Double = 0) -> Double {
        let available = max(width - separatorWidth, 0)
        guard available >= 2 * minimumColumnWidth else { return available * min(max(fraction, 0), 1) }
        return min(max(available * fraction, minimumColumnWidth), available - minimumColumnWidth)
    }

    /// The fraction stored for a separator dragged to `leadingWidth`.
    public static func fraction(leadingWidth: Double, width: Double, separatorWidth: Double = 0) -> Double {
        let available = width - separatorWidth
        guard available > 0 else { return 0.5 }
        let clamped = self.leadingWidth(fraction: leadingWidth / available, width: width, separatorWidth: separatorWidth)
        return clamped / available
    }
}

/// Space around each slot of the presenter (LAY-04). Global, not per document (LAY-05). The
/// raw values are the old app's `layoutPadding` user default in points.
public enum LayoutPadding: Int, Sendable, CaseIterable {
    case none = 0
    case small = 15
    case normal = 30

    public static let `default` = LayoutPadding.normal

    public var points: Double { Double(rawValue) }
}

// Encodes dictionaries keyed by these enums as JSON objects instead of key-value arrays.
extension PresenterSlot: CodingKeyRepresentable {}
extension PresenterArrangement: CodingKeyRepresentable {}
