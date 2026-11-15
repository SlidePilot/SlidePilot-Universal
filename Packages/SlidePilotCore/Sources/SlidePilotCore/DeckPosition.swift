/// The current page of a deck, always a valid index.
public struct DeckPosition: Sendable, Equatable {
    /// Zero-based index of the current page.
    public private(set) var page: Int
    public private(set) var pageCount: Int

    public init(page: Int = 0, pageCount: Int) {
        self.pageCount = max(pageCount, 1)
        self.page = 0
        show(page)
    }

    /// Goes to `index`, clamped to the first and last page.
    public mutating func show(_ index: Int) {
        page = min(max(index, 0), pageCount - 1)
    }

    public mutating func showNext() {
        show(page + 1)
    }

    public mutating func showPrevious() {
        show(page - 1)
    }

    /// A reloaded deck keeps the page; if it got shorter, the last page is shown (DOC-08).
    /// The old app kept the invalid index (DEF-18).
    public mutating func changePageCount(to newCount: Int) {
        pageCount = max(newCount, 1)
        show(page)
    }
}
