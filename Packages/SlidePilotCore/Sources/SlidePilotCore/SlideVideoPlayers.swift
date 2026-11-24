import Foundation

/// The video players of the shown slide (NAV-07), one per video file.
///
/// The presenter and the presentation share a player per file, so playback is mirrored like
/// in the old app. The bookkeeping decides which players live on when what is shown changes;
/// the caller creates players and pauses the ones handed back as dropped. `Player` is generic
/// so Core stays free of AVFoundation.
public struct SlideVideoPlayers<Player> {
    /// The page whose videos own the players.
    public private(set) var page: Int?
    private var players: [URL: Player] = [:]

    public init() {}

    /// The files that have a player.
    public var files: Set<URL> { Set(players.keys) }

    /// The shared player for the video at `url` on `page`, made with `make` if there is none.
    /// Asking for another page first shows that page.
    public mutating func player(for url: URL, on page: Int, make: () -> Player) -> (player: Player, dropped: [Player]) {
        let dropped = show(page: page)
        if let player = players[url] { return (player, dropped) }
        let player = make()
        players[url] = player
        return (player, dropped)
    }

    /// Shows `page` and returns the players to stop. A new page drops every player, like the
    /// old app when the slide changed.
    public mutating func show(page: Int) -> [Player] {
        guard page != self.page else { return [] }
        self.page = page
        return removePlayers { _ in true }
    }

    /// After a reload of the document (DOC-08), `page` shows the videos in `files`. A video
    /// whose file is still there keeps its player and position; the players of the others
    /// are returned to stop (#138). A reload read for a page that is no longer shown changes
    /// nothing.
    public mutating func reloaded(page: Int, showing files: Set<URL>) -> [Player] {
        guard page == self.page else { return [] }
        return removePlayers { !files.contains($0) }
    }

    /// Drops every player, e.g. when the document closes.
    public mutating func removeAll() -> [Player] {
        removePlayers { _ in true }
    }

    private mutating func removePlayers(where shouldRemove: (URL) -> Bool) -> [Player] {
        let removed = players.filter { shouldRemove($0.key) }
        for url in removed.keys { players[url] = nil }
        return Array(removed.values)
    }
}

extension SlideVideoPlayers: Sendable where Player: Sendable {}
