import CoreGraphics
import Foundation

/// A video on a page as the player bookkeeping sees it (NAV-07).
public struct SlideVideo: Sendable, Hashable {
    /// The resolved file or web address.
    public var file: URL
    /// Where the page places the video, in PDF points.
    public var area: CGRect
    /// The page plays the video when it is shown (Beamer `autostart`).
    public var autostarts: Bool

    public init(file: URL, area: CGRect, autostarts: Bool = false) {
        self.file = file
        self.area = area
        self.autostarts = autostarts
    }

    /// The largest difference of an edge, in points, that still counts as the same place.
    public static let placementTolerance: CGFloat = 0.5

    /// Whether `other` shows the same file at the same place, so a player can carry over
    /// from one overlay build step to the next (#140).
    public func isSamePlacement(as other: SlideVideo) -> Bool {
        guard file == other.file else { return false }
        let a = area.standardized
        let b = other.area.standardized
        return [(a.minX, b.minX), (a.minY, b.minY), (a.maxX, b.maxX), (a.maxY, b.maxY)]
            .allSatisfy { abs($0 - $1) <= Self.placementTolerance }
    }
}

/// The video players of the shown slide (NAV-07).
///
/// The presenter and the presentation share a player per file, so playback is mirrored like
/// in the old app. The bookkeeping decides which players live on when what is shown changes;
/// the caller creates players, pauses the ones handed back as dropped and plays the ones
/// handed back to start. `Player` is generic so Core stays free of AVFoundation.
///
/// A step to the next or previous page keeps the player of each video that the new page
/// shows again with the same file at the same place (overlay build steps, #140). Until the
/// new page's videos are known (`settle`), the previous page's players wait as candidates.
public struct SlideVideoPlayers<Player> {
    /// What the caller does with players after a change.
    public struct Changes {
        /// Players to pause for good: no shown video uses them.
        public var dropped: [Player] = []
        /// Kept players whose video autostarts only from the new build step on.
        public var toStart: [Player] = []

        public init(dropped: [Player] = [], toStart: [Player] = []) {
            self.dropped = dropped
            self.toStart = toStart
        }
    }

    fileprivate struct Entry {
        var video: SlideVideo
        let player: Player
    }

    /// The page whose videos own the players.
    public private(set) var page: Int?
    private var entries: [Entry] = []
    /// The previous page's players after a step, until the new page claims or drops them.
    private var candidates: [Entry] = []

    public init() {}

    /// The files that have a player on the shown page.
    public var files: Set<URL> { Set(entries.map(\.video.file)) }

    /// Whether players of the previous page wait for `settle`.
    public var hasCandidates: Bool { !candidates.isEmpty }

    /// The shared player for `video` on `page`, made with `make` if there is none. Videos
    /// of one file on a page share a player, so the first one's activation applies. Asking
    /// for another page first shows that page as a jump.
    public mutating func player(for video: SlideVideo, on page: Int, make: () -> Player) -> (player: Player, changes: Changes) {
        var changes = Changes(dropped: show(page: page, change: .jump))
        if let entry = entries.first(where: { $0.video.file == video.file }) {
            return (entry.player, changes)
        }
        if let index = candidates.firstIndex(where: { $0.video.isSamePlacement(as: video) }) {
            let entry = claim(candidate: index, for: video, changes: &changes)
            return (entry.player, changes)
        }
        let player = make()
        entries.append(Entry(video: video, player: player))
        return (player, changes)
    }

    /// Shows `page` and returns the players to stop. A step to the page next to the shown
    /// one keeps the players as candidates for `settle`; any other change drops them all,
    /// like the old app when the slide changed.
    public mutating func show(page: Int, change: PageChange) -> [Player] {
        guard page != self.page else { return [] }
        // Candidates of an earlier step that no video claimed are not on this page.
        var dropped = candidates.map(\.player)
        let isAdjacentStep = change == .step && self.page.map { abs($0 - page) == 1 } == true
        if isAdjacentStep {
            candidates = entries
        } else {
            candidates = []
            dropped += entries.map(\.player)
        }
        entries = []
        self.page = page
        return dropped
    }

    /// Once the videos of `page` are known after a step: each candidate whose file the page
    /// shows at the same place keeps playing, the others are dropped. A settle for a page
    /// that is no longer shown changes nothing.
    public mutating func settle(page: Int, showing videos: [SlideVideo]) -> Changes {
        guard page == self.page else { return Changes() }
        var changes = Changes()
        for video in videos where !entries.contains(where: { $0.video.file == video.file }) {
            if let index = candidates.firstIndex(where: { $0.video.isSamePlacement(as: video) }) {
                _ = claim(candidate: index, for: video, changes: &changes)
            }
        }
        changes.dropped += candidates.map(\.player)
        candidates = []
        return changes
    }

    /// After a reload of the document (DOC-08), `page` shows the videos in `files`. A video
    /// whose file is still there keeps its player and position; the players of the others
    /// are returned to stop (#138). A reload read for a page that is no longer shown changes
    /// nothing.
    public mutating func reloaded(page: Int, showing files: Set<URL>) -> [Player] {
        guard page == self.page else { return [] }
        let removed = entries.filter { !files.contains($0.video.file) }
        entries.removeAll { !files.contains($0.video.file) }
        return removed.map(\.player)
    }

    /// Drops every player, e.g. when the document closes.
    public mutating func removeAll() -> [Player] {
        let all = (entries + candidates).map(\.player)
        entries = []
        candidates = []
        return all
    }

    /// Moves a candidate to the shown page. An autostart that appears only on this build
    /// step starts the kept video; one that already autostarted is left as it is, so a
    /// playing video is not restarted and a paused one stays paused.
    private mutating func claim(candidate index: Int, for video: SlideVideo, changes: inout Changes) -> Entry {
        let old = candidates.remove(at: index)
        let entry = Entry(video: video, player: old.player)
        entries.append(entry)
        if video.autostarts, !old.video.autostarts {
            changes.toStart.append(old.player)
        }
        return entry
    }
}

extension SlideVideoPlayers: Sendable where Player: Sendable {}
extension SlideVideoPlayers.Changes: Sendable where Player: Sendable {}
extension SlideVideoPlayers.Entry: Sendable where Player: Sendable {}
