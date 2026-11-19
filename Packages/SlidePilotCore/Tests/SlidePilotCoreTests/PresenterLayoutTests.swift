import Foundation
import SlidePilotCore
import Testing

@Suite
struct PresenterLayoutTests {
    // LAY-01: the old default is double with [current, next, notes].
    @Test func defaultShowsCurrentAndNext() {
        let layout = PresenterLayout.default
        #expect(layout.arrangement == .double)
        #expect(layout.slots == [.current, .next, .notes])
        #expect(layout.visibleSlots == [.current, .next])
        #expect(!layout.isVisible(.notes))
    }

    // LAY-02: showing notes from double goes to tripleLeft; without a remembered position
    // the shown slot is inserted at index 1 (old showSlide), so the current slide is large.
    @Test func showingNotesFromDefaultGoesToTripleLeft() {
        var layout = PresenterLayout.default
        layout.setVisible(.notes, true)
        #expect(layout.arrangement == .tripleLeft)
        #expect(layout.slots == [.next, .notes, .current])
    }

    // LAY-02: hiding and showing a slot restores the triple arrangement and slot positions.
    @Test func hideAndShowRestoresTripleLeft() {
        var layout = PresenterLayout(arrangement: .tripleLeft, slots: [.next, .notes, .current])
        layout.toggle(.notes)
        #expect(layout.arrangement == .double)
        #expect(layout.slots == [.current, .next, .notes])
        layout.toggle(.notes)
        #expect(layout.arrangement == .tripleLeft)
        #expect(layout.slots == [.next, .notes, .current])
    }

    @Test func hideAndShowRestoresTripleRight() {
        var layout = PresenterLayout(arrangement: .tripleRight)
        layout.setVisible(.next, false)
        #expect(layout.arrangement == .double)
        #expect(layout.slots == [.current, .notes, .next])
        layout.setVisible(.next, true)
        #expect(layout.arrangement == .tripleRight)
        #expect(layout.slots == [.current, .next, .notes])
    }

    @Test func hideAndShowFromDoubleRestoresPosition() {
        var layout = PresenterLayout.default
        layout.setVisible(.current, false)
        #expect(layout.arrangement == .single)
        #expect(layout.visibleSlots == [.next])
        layout.setVisible(.current, true)
        #expect(layout.arrangement == .double)
        #expect(layout.slots == [.current, .next, .notes])
    }

    // DEF-16: a layout without the current slide is valid; the view keeps updating the others.
    @Test func layoutWithoutCurrentSlide() {
        var layout = PresenterLayout.default
        layout.setVisible(.current, false)
        layout.setVisible(.notes, true)
        #expect(layout.visibleSlots == [.next, .notes])
        #expect(!layout.isVisible(.current))
    }

    // The window is never empty: hiding the only slot shows the current slide instead.
    @Test func hidingOnlySlotShowsCurrentSlide() {
        var layout = PresenterLayout(arrangement: .single, slots: [.next, .current, .notes])
        layout.setVisible(.next, false)
        #expect(layout.arrangement == .single)
        #expect(layout.visibleSlots == [.current])

        layout.setVisible(.current, false)
        #expect(layout.visibleSlots == [.current])
    }

    // Do not replicate: the old app turned double into triple when notes were "shown" again.
    @Test func showingVisibleSlotDoesNothing() {
        var layout = PresenterLayout.default
        layout.setVisible(.current, true)
        #expect(layout == .default)
        layout.setVisible(.notes, false)
        #expect(layout == .default)
    }

    @Test func arrangementKeepsSlotOrder() {
        var layout = PresenterLayout.default
        layout.setArrangement(.tripleRight)
        #expect(layout.visibleSlots == [.current, .next, .notes])
        layout.setArrangement(.single)
        #expect(layout.visibleSlots == [.current])
    }

    // LAY-03: separator positions are kept per arrangement and clamped.
    @Test func separatorPositionsPerArrangement() {
        var layout = PresenterLayout.default
        #expect(layout.leadingFraction(in: .double) == 0.6)
        #expect(layout.leadingFraction(in: .tripleRight) == 0.4)
        layout.setLeadingFraction(0.3, in: .double)
        layout.setLeadingFraction(1.5, in: .tripleLeft)
        layout.setLeadingFraction(.nan, in: .tripleRight)
        #expect(layout.leadingFraction(in: .double) == 0.3)
        #expect(layout.leadingFraction(in: .tripleLeft) == 1)
        #expect(layout.leadingFraction(in: .tripleRight) == 0.4)
    }

    // LAY-04: choosing a slide for a slot swaps it with the slide there, like dropping a
    // slide symbol on a slot in the old editor (moveSlide swap: true).
    @Test func setSlotSwapsVisibleSlots() {
        var layout = PresenterLayout.default
        layout.setSlot(.next, at: 0)
        #expect(layout.slots == [.next, .current, .notes])
        #expect(layout.arrangement == .double)
    }

    // LAY-04: a hidden slide put into a slot replaces the slide there, which becomes hidden.
    @Test func setSlotShowsHiddenSlide() {
        var layout = PresenterLayout.default
        layout.setSlot(.notes, at: 1)
        #expect(layout.visibleSlots == [.current, .notes])
        #expect(!layout.isVisible(.next))

        var single = PresenterLayout(arrangement: .single)
        single.setSlot(.notes, at: 0)
        #expect(single.visibleSlots == [.notes])
    }

    // LAY-04: the slot pickers list the visible slots as they appear, large slot first in
    // tripleLeft, and name each by its place.
    @Test func slotPlacesInVisualOrder() {
        let places = PresenterArrangement.allCases.map { arrangement in
            arrangement.slotIndicesInVisualOrder.map { arrangement.place(ofSlotAt: $0) }
        }
        #expect(places == [
            [.whole],
            [.left, .right],
            [.largeLeft, .topRight, .bottomRight],
            [.topLeft, .bottomLeft, .largeRight],
        ])
        #expect(PresenterArrangement.double.place(ofSlotAt: 2) == nil)
        for arrangement in PresenterArrangement.allCases {
            #expect(arrangement.slotIndicesInVisualOrder.sorted() == Array(0..<arrangement.slotCount))
        }
    }

    @Test func setSlotIgnoresSameSlotAndInvalidPosition() {
        var layout = PresenterLayout(arrangement: .tripleRight, slots: [.next, .notes, .current])
        layout.setSlot(.notes, at: 1)
        layout.setSlot(.current, at: 3)
        layout.setSlot(.current, at: -1)
        #expect(layout.slots == [.next, .notes, .current])
    }

    @Test func invalidSlotsFallBackToDefaultOrder() {
        let layout = PresenterLayout(arrangement: .tripleLeft, slots: [.current, .current, .notes])
        #expect(layout.slots == [.current, .next, .notes])
    }

    // LAY-05: the stored layout keeps the remembered triple and slot position.
    @Test func codableRoundTripKeepsMemory() throws {
        var layout = PresenterLayout(arrangement: .tripleRight)
        layout.setLeadingFraction(0.45, in: .tripleRight)
        layout.setVisible(.next, false)
        let decoded = try JSONDecoder().decode(PresenterLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
        var restored = decoded
        restored.setVisible(.next, true)
        #expect(restored.arrangement == .tripleRight)
        #expect(restored.slots == [.current, .next, .notes])
        #expect(restored.leadingFraction(in: .tripleRight) == 0.45)
    }

    @Test func decodingDamagedLayoutFallsBack() throws {
        let json = Data(#"{"arrangement":"quadruple","slots":["notes"],"leadingFractions":{"double":0.7}}"#.utf8)
        let layout = try JSONDecoder().decode(PresenterLayout.self, from: json)
        #expect(layout.arrangement == .double)
        #expect(layout.slots == [.current, .next, .notes])
        #expect(layout.leadingFraction(in: .double) == 0.7)
    }
}

@Suite
struct PresenterSplitTests {
    // LAY-03: each column is at least 300 pt wide.
    @Test func clampsToMinimumColumnWidth() {
        #expect(PresenterSplit.leadingWidth(fraction: 0.1, width: 1000) == 300)
        #expect(PresenterSplit.leadingWidth(fraction: 0.9, width: 1000) == 700)
        #expect(PresenterSplit.leadingWidth(fraction: 0.5, width: 1000) == 500)
        #expect(PresenterSplit.fraction(leadingWidth: 100, width: 1000) == 0.3)
    }

    // iPad portrait or a narrow window: the columns stack instead.
    @Test func fitsSideBySide() {
        #expect(PresenterSplit.fitsSideBySide(width: 601, separatorWidth: 1))
        #expect(!PresenterSplit.fitsSideBySide(width: 599))
        #expect(!PresenterSplit.stacksVertically(width: 1366, height: 1000))
        #expect(PresenterSplit.stacksVertically(width: 1024, height: 1300))
        #expect(PresenterSplit.stacksVertically(width: 500, height: 400))
    }
}

@MainActor
@Suite
struct PresenterLayoutModelTests {
    // LAY-05: every change is saved as the last-used layout for the next document.
    @Test func savesEveryChangeAsLastUsed() {
        let store = InMemoryPresenterLayoutStore()
        let model = PresenterLayoutModel(store: store)
        #expect(model.layout == .default)
        #expect(store.layout == nil)

        model.toggle(.notes)
        model.setLeadingFraction(0.55, in: .tripleLeft)
        #expect(store.layout == model.layout)

        model.setSlot(.current, at: 0)
        #expect(store.layout?.slots.first == .current)

        let next = PresenterLayoutModel(store: store)
        #expect(next.arrangement == .tripleLeft)
        #expect(next.leadingFraction(in: .tripleLeft) == 0.55)
    }

    @Test func userDefaultsStoreRoundTrip() throws {
        let suite = "PresenterLayoutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPresenterLayoutStore(defaults: defaults)
        #expect(store.lastUsedLayout() == nil)
        let layout = PresenterLayout(arrangement: .single, slots: [.notes, .current, .next])
        store.saveLastUsedLayout(layout)
        #expect(UserDefaultsPresenterLayoutStore(defaults: defaults).lastUsedLayout() == layout)
    }
}
