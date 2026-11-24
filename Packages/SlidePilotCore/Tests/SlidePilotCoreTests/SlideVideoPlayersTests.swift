import CoreGraphics
import Foundation
import Testing
@testable import SlidePilotCore

@Suite struct SlideVideoPlayersTests {
    let intro = URL(filePath: "/talks/media/intro.mp4")
    let demo = URL(filePath: "/talks/media/demo.mp4")
    let left = CGRect(x: 20, y: 40, width: 160, height: 90)
    let right = CGRect(x: 200, y: 40, width: 160, height: 90)

    /// Counts made players, so a test can tell a kept player from a new one.
    private struct Maker {
        var count = 0
        mutating func make() -> Int {
            count += 1
            return count
        }
    }

    private func video(_ file: URL, _ area: CGRect? = nil, autostarts: Bool = false) -> SlideVideo {
        SlideVideo(file: file, area: area ?? left, autostarts: autostarts)
    }

    // MARK: - One page

    @Test func sharesOnePlayerPerFileOnAPage() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        let first = players.player(for: video(intro), on: 2) { maker.make() }
        let second = players.player(for: video(intro, right), on: 2) { maker.make() }
        #expect(first.player == 1)
        #expect(second.player == 1)
        #expect(second.changes.dropped.isEmpty)
        let other = players.player(for: video(demo), on: 2) { maker.make() }
        #expect(other.player == 2)
        #expect(players.files == [intro, demo])
    }

    @Test func jumpDropsEveryPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 2) { maker.make() }
        _ = players.player(for: video(demo, right), on: 2) { maker.make() }
        #expect(Set(players.show(page: 3, change: .jump)) == [1, 2])
        #expect(players.files.isEmpty)
        #expect(!players.hasCandidates)
        #expect(players.page == 3)
    }

    @Test func showingTheSamePageKeepsThePlayers() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 2) { maker.make() }
        #expect(players.show(page: 2, change: .jump).isEmpty)
        #expect(players.player(for: video(intro), on: 2) { maker.make() }.player == 1)
    }

    @Test func askingForAnotherPageDropsThePreviousPlayers() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 2) { maker.make() }
        let next = players.player(for: video(intro), on: 3) { maker.make() }
        #expect(next.changes.dropped == [1])
        #expect(next.player == 2)
    }

    // MARK: - Build steps (#140)

    @Test func stepToTheNextPageKeepsTheSameVideo() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        #expect(players.show(page: 8, change: .step).isEmpty)
        #expect(players.hasCandidates)
        let changes = players.settle(page: 8, showing: [video(intro)])
        #expect(changes.dropped.isEmpty)
        #expect(changes.toStart.isEmpty)
        let kept = players.player(for: video(intro), on: 8) { maker.make() }
        #expect(kept.player == 1)
        #expect(!players.hasCandidates)
    }

    @Test func stepBackKeepsTheSameVideo() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 9) { maker.make() }
        _ = players.show(page: 8, change: .step)
        #expect(players.settle(page: 8, showing: [video(intro)]).dropped.isEmpty)
        #expect(players.player(for: video(intro), on: 8) { maker.make() }.player == 1)
    }

    /// The new page's view may ask for its player before `settle`.
    @Test func viewCanClaimBeforeSettle() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        let kept = players.player(for: video(intro), on: 8) { maker.make() }
        #expect(kept.player == 1)
        #expect(kept.changes.dropped.isEmpty)
        #expect(players.settle(page: 8, showing: [video(intro)]).dropped.isEmpty)
        #expect(players.files == [intro])
    }

    @Test func jumpToTheNextPageRestarts() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        #expect(players.show(page: 8, change: .jump) == [1])
        #expect(!players.hasCandidates)
        #expect(players.player(for: video(intro), on: 8) { maker.make() }.player == 2)
    }

    /// Several next presses can arrive before the page change is seen; only a neighbor counts.
    @Test func stepOverMoreThanOnePageRestarts() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        #expect(players.show(page: 9, change: .step) == [1])
        #expect(players.player(for: video(intro), on: 9) { maker.make() }.player == 2)
    }

    @Test func differentFileRestarts() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        #expect(players.settle(page: 8, showing: [video(demo)]).dropped == [1])
        #expect(players.player(for: video(demo), on: 8) { maker.make() }.player == 2)
    }

    @Test func movedAreaRestarts() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        let moved = left.offsetBy(dx: 0.6, dy: 0)
        #expect(players.player(for: video(intro, moved), on: 8) { maker.make() }.player == 2)
        #expect(players.settle(page: 8, showing: [video(intro, moved)]).dropped == [1])
    }

    @Test func areaWithinHalfAPointIsTheSamePlace() {
        let a = video(intro)
        #expect(a.isSamePlacement(as: video(intro, left.insetBy(dx: 0.25, dy: -0.5))))
        #expect(a.isSamePlacement(as: video(intro, left.offsetBy(dx: -0.5, dy: 0.5))))
        #expect(!a.isSamePlacement(as: video(intro, left.insetBy(dx: 0, dy: 0.6))))
        #expect(!a.isSamePlacement(as: video(demo)))
    }

    @Test func decidesPerVideo() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro, left), on: 7) { maker.make() }
        _ = players.player(for: video(demo, right), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        // The demo moved to the left half's place, the intro stayed: only the intro carries over.
        let changes = players.settle(page: 8, showing: [video(intro, left), video(demo, left.offsetBy(dx: 0, dy: 100))])
        #expect(changes.dropped == [2])
        #expect(players.player(for: video(intro, left), on: 8) { maker.make() }.player == 1)
        #expect(players.player(for: video(demo, left.offsetBy(dx: 0, dy: 100)), on: 8) { maker.make() }.player == 3)
    }

    @Test func keepsPlayingThroughSeveralSteps() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        for page in [8, 9, 8, 7] {
            #expect(players.show(page: page, change: .step).isEmpty)
            #expect(players.settle(page: page, showing: [video(intro)]).dropped.isEmpty)
        }
        #expect(players.player(for: video(intro), on: 7) { maker.make() }.player == 1)
        #expect(maker.count == 1)
    }

    /// A step away and a jump back still restarts (Go Back, navigator).
    @Test func stepAwayAndJumpBackRestarts() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        #expect(players.settle(page: 8, showing: []).dropped == [1])
        #expect(players.show(page: 7, change: .jump).isEmpty)
        #expect(players.player(for: video(intro), on: 7) { maker.make() }.player == 2)
    }

    /// The next step comes before the previous one's videos were known.
    @Test func unclaimedCandidatesDropOnTheNextChange() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        #expect(players.show(page: 9, change: .step) == [1])
        #expect(players.settle(page: 8, showing: [video(intro)]).dropped.isEmpty)
        #expect(!players.hasCandidates)
    }

    @Test func autostartFromALaterStepStartsTheKeptVideo() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        #expect(players.settle(page: 8, showing: [video(intro, autostarts: true)]).toStart == [1])
        // From the view instead of settle.
        _ = players.show(page: 9, change: .step)
        #expect(players.player(for: video(intro, autostarts: true), on: 9) { maker.make() }.changes.toStart.isEmpty)
    }

    @Test func autostartOnEveryStepDoesNotRestart() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro, autostarts: true), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        let changes = players.settle(page: 8, showing: [video(intro, autostarts: true)])
        #expect(changes.toStart.isEmpty)
        #expect(changes.dropped.isEmpty)
    }

    @Test func viewClaimStartsAnAutostartFromALaterStep() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 7) { maker.make() }
        _ = players.show(page: 8, change: .step)
        #expect(players.player(for: video(intro, autostarts: true), on: 8) { maker.make() }.changes.toStart == [1])
    }

    // MARK: - Reload (#138)

    /// The reloaded slide no longer has the video, so its sound must stop.
    @Test func reloadWithoutTheVideoDropsItsPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 2) { maker.make() }
        #expect(players.reloaded(page: 2, showing: []) == [1])
        #expect(players.files.isEmpty)
    }

    /// The slide now refers to another file.
    @Test func reloadWithAnotherFileDropsTheOldPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 2) { maker.make() }
        #expect(players.reloaded(page: 2, showing: [demo]) == [1])
        #expect(players.player(for: video(demo), on: 2) { maker.make() }.player == 2)
    }

    @Test func reloadKeepsTheVideosThatAreStillThere() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 2) { maker.make() }
        _ = players.player(for: video(demo, right), on: 2) { maker.make() }
        #expect(players.reloaded(page: 2, showing: [intro]) == [2])
        // The same player, so it keeps playing at its position.
        let kept = players.player(for: video(intro), on: 2) { maker.make() }
        #expect(kept.player == 1)
        #expect(kept.changes.dropped.isEmpty)
    }

    @Test func reloadReadForAnOldPageChangesNothing() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 3) { maker.make() }
        #expect(players.reloaded(page: 2, showing: []).isEmpty)
        #expect(players.files == [intro])
    }

    @Test func removeAllDropsEveryPlayer() {
        var players = SlideVideoPlayers<Int>()
        var maker = Maker()
        _ = players.player(for: video(intro), on: 2) { maker.make() }
        _ = players.show(page: 3, change: .step)
        _ = players.player(for: video(demo), on: 3) { maker.make() }
        #expect(Set(players.removeAll()) == [1, 2])
        #expect(players.files.isEmpty)
        #expect(!players.hasCandidates)
    }
}
