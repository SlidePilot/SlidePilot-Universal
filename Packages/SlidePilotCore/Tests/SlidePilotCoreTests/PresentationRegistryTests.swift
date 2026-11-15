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

    @Test func newestSessionIsActive() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        registry.register(first)
        registry.register(second)
        #expect(registry.activeSession === second)
    }

    @Test func activatingMakesSessionActive() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        registry.register(first)
        registry.register(second)
        registry.activate(first.id)
        #expect(registry.activeSession === first)
    }

    @Test func unregisteringActiveFallsBackToPreviouslyActive() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        let second = Session()
        let third = Session()
        [first, second, third].forEach(registry.register)
        registry.activate(first.id)
        registry.unregister(first.id)
        #expect(registry.activeSession === third)
        #expect(registry.session(for: first.id) == nil)
        registry.unregister(third.id)
        registry.unregister(second.id)
        #expect(registry.activeSession == nil)
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

    @Test func activatingUnknownIDChangesNothing() {
        let registry = PresentationRegistry<Session>()
        let first = Session()
        registry.register(first)
        registry.activate(UUID())
        #expect(registry.activeSession === first)
    }
}
