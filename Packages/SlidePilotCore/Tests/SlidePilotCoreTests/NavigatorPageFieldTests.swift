import SlidePilotCore
import Testing

@Suite
struct NavigatorPageFieldTests {
    @Test(arguments: [("1", 0), ("7", 6), ("10", 9)])
    func numberPointsAtPage(text: String, page: Int) {
        #expect(NavigatorPageField.page(for: text, pageCount: 10) == page)
    }

    @Test func numbersOutsideTheDeckAreClamped() {
        #expect(NavigatorPageField.page(for: "0", pageCount: 10) == 0)
        #expect(NavigatorPageField.page(for: "-4", pageCount: 10) == 0)
        #expect(NavigatorPageField.page(for: "99", pageCount: 10) == 9)
    }

    @Test(arguments: ["", "a", "3a", " 3", "3.0"])
    func otherTextPointsAtNoPage(text: String) {
        #expect(NavigatorPageField.page(for: text, pageCount: 10) == nil)
    }

    @Test func emptyDeckHasNoPage() {
        #expect(NavigatorPageField.page(for: "1", pageCount: 0) == nil)
    }

    @Test func lettersAndDigitsStartInput() {
        #expect(NavigatorPageField.startsInput("4"))
        #expect(NavigatorPageField.startsInput("g"))
        #expect(NavigatorPageField.startsInput("Ä"))
        #expect(!NavigatorPageField.startsInput(" "))
        #expect(!NavigatorPageField.startsInput("-"))
        #expect(!NavigatorPageField.startsInput("\r"))
    }
}
