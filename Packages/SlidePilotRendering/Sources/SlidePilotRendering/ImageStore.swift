/// Identifies one rendition in the cache: one image per page and region (ADR 0005).
/// Smaller views scale the image down instead of rendering again.
struct SlideKey: Hashable, Sendable {
    let page: Int
    let region: PageRegion
}

/// Rendered images with their byte count and a least-recently-used order.
struct ImageStore {
    private struct Entry {
        var slide: RenderedSlide
        var lastUse: UInt64
    }

    private var entries: [SlideKey: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var usedBytes = 0

    var keys: Set<SlideKey> { Set(entries.keys) }

    /// Returns the image and marks it as recently used.
    mutating func use(_ key: SlideKey) -> RenderedSlide? {
        guard entries[key] != nil else { return nil }
        clock += 1
        entries[key]?.lastUse = clock
        return entries[key]?.slide
    }

    func peek(_ key: SlideKey) -> RenderedSlide? {
        entries[key]?.slide
    }

    /// Stores `slide`, replacing a smaller rendition of the same page and region.
    mutating func insert(_ slide: RenderedSlide, for key: SlideKey) {
        if let old = entries[key] {
            // Never replace a larger rendition with a smaller one.
            if old.slide.pixelSize.covers(slide.pixelSize), old.slide.pixelSize != slide.pixelSize {
                return
            }
            usedBytes -= old.slide.byteCount
        }
        clock += 1
        entries[key] = Entry(slide: slide, lastUse: clock)
        usedBytes += slide.byteCount
    }

    /// Evicts images until the store fits into `budget`: least recently used images
    /// outside `preferred` first, then those inside it. `protected` images stay.
    mutating func evict(toFit budget: Int, protected: Set<SlideKey>, preferred: Set<SlideKey>) {
        guard usedBytes > budget else { return }
        let candidates = entries
            .filter { !protected.contains($0.key) }
            .sorted { lhs, rhs in
                let lhsPreferred = preferred.contains(lhs.key)
                let rhsPreferred = preferred.contains(rhs.key)
                if lhsPreferred != rhsPreferred { return !lhsPreferred }
                return lhs.value.lastUse < rhs.value.lastUse
            }
        for candidate in candidates where usedBytes > budget {
            remove(candidate.key)
        }
    }

    /// Drops every image except those in `keep`.
    mutating func removeAll(except keep: Set<SlideKey>) {
        for key in entries.keys where !keep.contains(key) {
            remove(key)
        }
    }

    private mutating func remove(_ key: SlideKey) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        usedBytes -= entry.slide.byteCount
    }
}
