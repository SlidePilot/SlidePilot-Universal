import Foundation
import Testing
@testable import SlidePilotCore

@Suite struct SlideVideoPlayersTests {
    let intro = URL(filePath: "/talks/media/intro.mp4")
    let demo = URL(filePath: "/talks/media/demo.mp4")

    /// Counts made players, so a test can tell a kept player from a new one.
    private struct Maker {
        var count = 0
        mutating func make() -> Int {
            count += 1
            return count
        }
    }

    @Test func sharesOnePlayerPerFileOnAPage() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        let first = players.player(for: intro, on: 2) { maker.make() }
        let second = players.player(for: intro, on: 2) { maker.make() }
        #expect(first.player == 1)
        #expect(second.player == 1)
        #expect(second.dropped.isEmpty)
        let other = players.player(for: demo, on: 2) { maker.make() }
        #expect(other.player == 2)
        #expect(players.files == [intro, demo])
    }

    @Test func newPageDropsEveryPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 2) { maker.make() }
        _ = players.player(for: demo, on: 2) { maker.make() }
        #expect(Set(players.show(page: 3)) == [1, 2])
        #expect(players.files.isEmpty)
        #expect(players.page == 3)
    }

    @Test func showingTheSamePageKeepsThePlayers() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 2) { maker.make() }
        #expect(players.show(page: 2).isEmpty)
        #expect(players.player(for: intro, on: 2) { maker.make() }.player == 1)
    }

    @Test func askingForAnotherPageDropsThePreviousPlayers() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 2) { maker.make() }
        let next = players.player(for: intro, on: 3) { maker.make() }
        #expect(next.dropped == [1])
        #expect(next.player == 2)
    }

    /// #138: the reloaded slide no longer has the video, so its sound must stop.
    @Test func reloadWithoutTheVideoDropsItsPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 2) { maker.make() }
        #expect(players.reloaded(page: 2, showing: []) == [1])
        #expect(players.files.isEmpty)
    }

    /// #138: the slide now refers to another file.
    @Test func reloadWithAnotherFileDropsTheOldPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 2) { maker.make() }
        #expect(players.reloaded(page: 2, showing: [demo]) == [1])
        #expect(players.player(for: demo, on: 2) { maker.make() }.player == 2)
    }

    @Test func reloadKeepsTheVideosThatAreStillThere() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 2) { maker.make() }
        _ = players.player(for: demo, on: 2) { maker.make() }
        #expect(players.reloaded(page: 2, showing: [intro]) == [2])
        // The same player, so it keeps playing at its position.
        let kept = players.player(for: intro, on: 2) { maker.make() }
        #expect(kept.player == 1)
        #expect(kept.dropped.isEmpty)
    }

    @Test func reloadReadForAnOldPageChangesNothing() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 3) { maker.make() }
        #expect(players.reloaded(page: 2, showing: []).isEmpty)
        #expect(players.files == [intro])
    }

    @Test func removeAllDropsEveryPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: intro, on: 2) { maker.make() }
        #expect(players.removeAll() == [1])
        #expect(players.files.isEmpty)
    }
}
