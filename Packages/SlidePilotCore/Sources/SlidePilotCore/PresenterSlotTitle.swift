/// The one-line title above a presenter slot (LAY-10).
///
/// Changed against the old app ("Current Slide n / count", "Next Slide", "Notes Slide
/// n / count"; product-owner decision 2026-11-25): shorter titles, and only the current
/// slot shows the counter.
public enum PresenterSlotTitle: Sendable, Equatable {
    /// The current slide with its one-based number and the page count.
    case current(SlideCounter)
    /// The next slide preview.
    case next
    /// The next slot after the last slide (old app: "Finished Presentation").
    case endOfPresentation
    /// The notes slot, split notes or text notes.
    case notes

    public init(slot: PresenterSlot, position: DeckPosition) {
        switch slot {
        case .current: self = .current(SlideCounter(position))
        case .next: self = position.isOnLastPage ? .endOfPresentation : .next
        case .notes: self = .notes
        }
    }
}

/// Where the talk stands: "7 / 18" on screen, "Slide 7 of 18" for VoiceOver and the Mac
/// window subtitle (LAY-10).
public struct SlideCounter: Sendable, Equatable {
    /// One-based number of the current slide.
    public let number: Int
    public let count: Int

    public init(number: Int, count: Int) {
        self.number = number
        self.count = count
    }

    public init(_ position: DeckPosition) {
        self.init(number: position.page + 1, count: position.pageCount)
    }
}

extension DeckPosition {
    /// The current page is the deck's last one, so no slide follows (LAY-09, LAY-10).
    public var isOnLastPage: Bool {
        page == pageCount - 1
    }
}
