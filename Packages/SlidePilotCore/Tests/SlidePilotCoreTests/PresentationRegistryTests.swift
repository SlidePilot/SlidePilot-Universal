import Foundation
import SlidePilotCore
import Testing

@MainActor
@Suite
struct PresentationRegistryTests {
    final class Session: Identifiable {
        let id = UUID()
    }

    @Test func emptyRegistryHasNoActiveSession() {
        #expect(PresentationRegistry<Session>().activeSession == nil)
    }

    @Test func findsSessionByID() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        registry.register(first)
        registry.register(second)
        #expect(registry.session(for: first.id) === first)
        #expect(registry.session(for: UUID()) == nil)
    }

    @Test func listsSessionsInOpeningOrderOnce() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        registry.register(first)
        registry.register(second)
        registry.register(first, inWindow: "window")
        #expect(registry.sessions.map(\.id) == [first.id, second.id])
        registry.unregister(first.id)
        #expect(registry.sessions.map(\.id) == [second.id])
    }

    @Test func withoutWindowsNewestSessionIsActive() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        registry.register(first)
        registry.register(second)
        #expect(registry.activeSession === second)
        registry.unregister(second.id)
        #expect(registry.activeSession === first)
    }

    @Test func registeringTwiceKeepsOneEntry() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        registry.register(first)
        registry.register(second)
        registry.register(first)
        #expect(registry.activeSession === second)
        registry.unregister(first.id)
        #expect(registry.session(for: first.id) == nil)
    }

    @Test func findsSessionByWindow() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        registry.register(first)
        #expect(registry.session(inWindow: "A") == nil)
        registry.register(first, inWindow: "A")
        #expect(registry.session(inWindow: "A") === first)
        #expect(registry.session(inWindow: "B") == nil)
    }

    // Hardware test: two windows on iPad, switching between them.
    @Test func activeWindowDecidesActiveSession() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        registry.activateWindow("A")
        registry.register(first, inWindow: "A")
        #expect(registry.activeSession === first)
        registry.activateWindow("B")
        #expect(registry.activeSession == nil)
        registry.register(second, inWindow: "B")
        #expect(registry.activeSession === second)
        registry.activateWindow("A")
        #expect(registry.activeSession === first)
        registry.unregister(first.id)
        #expect(registry.activeSession == nil)
    }

    @Test func newDocumentInSameWindowReplacesOldOne() {
        let registry = PresentationRegistry<Session>()
        let old = Session()
        let new = Session()
        registry.activateWindow("A")
        registry.register(old, inWindow: "A")
        // The new document can appear before the old one disappears.
        registry.register(new, inWindow: "A")
        registry.unregister(old.id)
        #expect(registry.activeSession === new)
    }
}
