/// The current page of a deck, always a valid index, and the previously viewed page
/// for "Go Back" (NAV-03).
public struct DeckPosition: Sendable, Equatable {
    /// Zero-based index of the current page.
    public private(set) var page: Int
    public private(set) var pageCount: Int
    /// The page shown before the last page change, the target of `goBack()`. Every change
    /// counts: a step, a jump (navigator, link) and going back itself, so going back twice
    /// returns to where you were. `nil` until the page changed for the first time.
    public private(set) var previousPage: Int?

    public init(page: Int = 0, pageCount: Int) {
        self.pageCount = max(pageCount, 1)
        self.page = min(max(page, 0), self.pageCount - 1)
    }

    public var canGoBack: Bool {
        previousPage != nil
    }

    /// Goes to `index`, clamped to the first and last page. Staying on the same page
    /// (e.g. "next" on the last page) keeps the previous page.
    public mutating func show(_ index: Int) {
        let target = min(max(index, 0), pageCount - 1)
        guard target != page else { return }
        previousPage = page
        page = target
    }

    public mutating func showNext() {
        show(page + 1)
    }

    public mutating func showPrevious() {
        show(page - 1)
    }

    /// Shows the previously viewed page (NAV-03).
    public mutating func goBack() {
        guard let previousPage else { return }
        show(previousPage)
    }

    /// A reloaded deck keeps the page; if it got shorter, the last page is shown (DOC-08).
    /// The old app kept the invalid index (DEF-18). A reload is not a page change for
    /// "Go Back": the previous page stays unless it no longer exists or is now current.
    /// (The old app overwrote it with the current page, so Go Back did nothing after a reload.)
    public mutating func changePageCount(to newCount: Int) {
        pageCount = max(newCount, 1)
        page = min(page, pageCount - 1)
        if let previousPage, previousPage >= pageCount || previousPage == page {
            self.previousPage = nil
        }
    }
}
