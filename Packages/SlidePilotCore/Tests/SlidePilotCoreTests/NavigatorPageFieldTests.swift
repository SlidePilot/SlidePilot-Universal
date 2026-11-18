import SlidePilotCore
import Testing

@Suite
struct NavigatorPageFieldTests {
    @Test func numberIsOneBased() {
        #expect(NavigatorPageField.page(for: "1", pageCount: 10) == 0)
        #expect(NavigatorPageField.page(for: "7", pageCount: 10) == 6)
        #expect(NavigatorPageField.page(for: " 3 ", pageCount: 10) == 2)
    }

    // The old app clamped the highlight to the first and last page.
    @Test func numberOutsideTheDeckIsClamped() {
        #expect(NavigatorPageField.page(for: "0", pageCount: 10) == 0)
        #expect(NavigatorPageField.page(for: "-4", pageCount: 10) == 0)
        #expect(NavigatorPageField.page(for: "42", pageCount: 10) == 9)
    }

    @Test func otherTextHighlightsNothing() {
        #expect(NavigatorPageField.page(for: "", pageCount: 10) == nil)
        #expect(NavigatorPageField.page(for: "intro", pageCount: 10) == nil)
        #expect(NavigatorPageField.page(for: "3a", pageCount: 10) == nil)
        #expect(NavigatorPageField.page(for: "99999999999999999999999", pageCount: 10) == nil)
    }

    @Test func emptyDeckHighlightsNothing() {
        #expect(NavigatorPageField.page(for: "1", pageCount: 0) == nil)
    }

    @Test func lettersAndDigitsStartInput() {
        #expect(NavigatorPageField.startsInput("4"))
        #expect(NavigatorPageField.startsInput("x"))
        #expect(!NavigatorPageField.startsInput(" "))
        #expect(!NavigatorPageField.startsInput("."))
        #expect(!NavigatorPageField.startsInput("\u{1B}"))
    }
}
