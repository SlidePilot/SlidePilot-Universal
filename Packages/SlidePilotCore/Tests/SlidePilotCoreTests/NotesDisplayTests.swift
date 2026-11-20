import Foundation
import SlidePilotCore
import Testing

@Suite struct NotesDisplayTests {
    // NOTES-03: exact, case-sensitive keywords; the first match wins.
    @Test(arguments: [
        ("SP-Right", NotesPosition.right),
        ("SP-Left", .left),
        ("SP-Top", .top),
        ("SP-Bottom", .bottom),
    ])
    func detectsKeyword(_ keyword: String, _ position: NotesPosition) {
        #expect(NotesPosition(pdfKeywords: ["Beamer", keyword]) == position)
        #expect(NotesDisplay(pdfKeywords: [keyword]) == NotesDisplay(mode: .split, position: position))
    }

    @Test func ignoresOtherSpellings() {
        #expect(NotesPosition(pdfKeywords: ["sp-right", "SP-RIGHT", " SP-Right", "SP-Right ", "Beamer, SP-Left"]) == nil)
        #expect(NotesPosition(pdfKeywords: []) == nil)
        #expect(NotesDisplay(pdfKeywords: ["sp-right"]) == .default)
    }

    @Test func firstKeywordWins() {
        #expect(NotesPosition(pdfKeywords: ["SP-Left", "SP-Right"]) == .left)
    }

    @Test func defaultIsTextOnWholePages() {
        #expect(NotesDisplay.default.mode == .text)
        #expect(NotesDisplay.default.position == .none)
        #expect(!NotesDisplay.default.showsSplitNotes)
    }

    // NOTES-02: choosing Split while the position is None sets Right.
    @Test func splitWithoutPositionSetsRight() {
        var display = NotesDisplay.default
        display.setMode(.split, notesShown: true)
        #expect(display == NotesDisplay(mode: .split, position: .right))
        #expect(display.showsSplitNotes)
    }

    @Test func splitKeepsAChosenPosition() {
        var display = NotesDisplay(mode: .text, position: .top)
        display.setMode(.split, notesShown: true)
        #expect(display.position == .top)
    }

    // NOTES-02: choosing Text sets None.
    @Test func textResetsThePosition() {
        var display = NotesDisplay(mode: .split, position: .left)
        display.setMode(.text, notesShown: true)
        #expect(display == .default)
    }

    // NOTES-02: choosing None switches to Text.
    @Test func noneSwitchesToText() {
        var display = NotesDisplay(mode: .split, position: .bottom)
        display.setPosition(.none, notesShown: true)
        #expect(display == .default)
    }

    @Test func positionKeepsTheMode() {
        var display = NotesDisplay(mode: .split, position: .right)
        display.setPosition(.top, notesShown: true)
        #expect(display == NotesDisplay(mode: .split, position: .top))
        var text = NotesDisplay.default
        text.setPosition(.left, notesShown: true)
        #expect(text == NotesDisplay(mode: .text, position: .left))
    }

    // The old app coupled mode and position only while the notes were displayed.
    @Test func hiddenNotesDoNotCouple() {
        var display = NotesDisplay(mode: .split, position: .left)
        display.setMode(.text, notesShown: false)
        #expect(display == NotesDisplay(mode: .text, position: .left))
        display.setMode(.split, notesShown: false)
        display.setPosition(.none, notesShown: false)
        #expect(display == NotesDisplay(mode: .split, position: .none))
        #expect(!display.showsSplitNotes)
    }

    // Showing the notes in Split mode without a position shows the right half.
    @Test func showingNotesInSplitModeSetsRight() {
        var display = NotesDisplay(mode: .split, position: .none)
        display.notesDidShow()
        #expect(display == NotesDisplay(mode: .split, position: .right))
        var text = NotesDisplay.default
        text.notesDidShow()
        #expect(text == .default)
        var placed = NotesDisplay(mode: .split, position: .top)
        placed.notesDidShow()
        #expect(placed.position == .top)
    }

    // SET-02: stored settings are coupled like the old load(configuration:).
    @Test func storedSettingsCoupleWhileNotesAreShown() {
        var text = NotesDisplay(pdfKeywords: ["SP-Right"])
        text.applyStored(mode: .text, position: .left, notesShown: true)
        #expect(text == .default)
        var split = NotesDisplay.default
        split.applyStored(mode: .split, position: NotesPosition.none, notesShown: true)
        #expect(split == NotesDisplay(mode: .split, position: .right))
        var hidden = NotesDisplay(pdfKeywords: ["SP-Top"])
        hidden.applyStored(mode: .text, position: .left, notesShown: false)
        #expect(hidden == NotesDisplay(mode: .text, position: .left))
        var nothing = NotesDisplay(pdfKeywords: ["SP-Top"])
        nothing.applyStored(mode: nil, position: nil, notesShown: true)
        #expect(nothing == NotesDisplay(mode: .split, position: .top))
    }

    // SET-02: mode and position are stored per document and optional.
    @Test func settingsRoundTrip() throws {
        var settings = DocumentSettings()
        settings.notesMode = .split
        settings.notesPosition = .bottom
        #expect(!settings.isEmpty)
        let decoded = try JSONDecoder().decode(DocumentSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        let empty = try JSONDecoder().decode(DocumentSettings.self, from: Data("{}".utf8))
        #expect(empty.notesMode == nil)
        #expect(empty.notesPosition == nil)
    }

    @Test func unknownValuesReadAsNotSaved() throws {
        let json = Data(#"{"notesMode":"video","notesPosition":"center","isNavigatorDisplayed":true}"#.utf8)
        let decoded = try JSONDecoder().decode(DocumentSettings.self, from: json)
        #expect(decoded.notesMode == nil)
        #expect(decoded.notesPosition == nil)
        #expect(decoded.isNavigatorDisplayed == true)
    }
}
