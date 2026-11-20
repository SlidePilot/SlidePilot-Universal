import Foundation
import SlidePilotCore
import Testing

private let a = RelativePoint(x: 0.1, y: 0.2)
private let b = RelativePoint(x: 0.3, y: 0.4)

private func stroke(_ color: StrokeColor = .blue, _ points: [RelativePoint] = [a, b]) -> DrawingStroke {
    DrawingStroke(color: color, points: points)
}

private func entry(drawings: CompanionDrawings?) -> CompanionEntry {
    CompanionEntry(
        pdf: PDFReference(bookmark: Data([1]), fileName: "talk.pdf", pageCount: 5),
        lastOpened: Date(timeIntervalSince1970: 0),
        drawings: drawings
    )
}

/// DRAW-07: the stored format of the drawings in the companion file.
@Suite
struct CompanionDrawingsTests {
    @Test func roundTrip() throws {
        let drawings = CompanionDrawings(pages: [
            0: PageDrawing(strokes: [stroke(), stroke(.orange, [b])], background: .transparent),
            3: PageDrawing(strokes: [], background: .white),
        ])
        let decoded = try CompanionFileFormat.decode(CompanionFileFormat.encode(entry(drawings: drawings)))
        #expect(decoded.entry.drawings == drawings)
        #expect(decoded.formatVersion == 1)
    }

    // The format is self-contained: a tag, sorted pages, interleaved points and RGBA colors.
    @Test func writesTheDocumentedShape() throws {
        let drawings = CompanionDrawings(pages: [
            2: PageDrawing(strokes: [stroke(.black)]),
            0: PageDrawing(background: .white),
        ])
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(drawings)) as? [String: Any])
        #expect(json["format"] as? String == "relative-strokes")
        let pages = try #require(json["pages"] as? [[String: Any]])
        #expect(pages.map { $0["page"] as? Int } == [0, 2])
        #expect(pages[0]["background"] as? String == "white")
        let strokes = try #require(pages[1]["strokes"] as? [[String: Any]])
        #expect(strokes[0]["points"] as? [Double] == [0.1, 0.2, 0.3, 0.4])
        #expect(strokes[0]["color"] as? [Double] == [0, 0, 0, 1])
    }

    // Points are rounded to 1/100 000 of the page, which keeps the file small.
    @Test func roundsPoints() throws {
        let drawings = CompanionDrawings(pages: [0: PageDrawing(strokes: [stroke(.black, [RelativePoint(x: 0.123456789, y: 1 / 3)])])])
        let decoded = try JSONDecoder().decode(CompanionDrawings.self, from: JSONEncoder().encode(drawings))
        #expect(decoded.pages[0]?.strokes[0].points == [RelativePoint(x: 0.12346, y: 0.33333)])
    }

    // Empty pages are not stored; drawings without any page are empty.
    @Test func dropsEmptyPages() {
        let drawings = CompanionDrawings(pages: [0: PageDrawing(), 1: PageDrawing(background: .transparent)])
        #expect(drawings.isEmpty)
        #expect(drawings.pages.isEmpty)
    }

    @Test(arguments: [
        #"{"format":"future","pages":[]}"#,
        #"{"format":"relative-strokes","pages":[{"page":-1,"background":"white","strokes":[]}]}"#,
        #"{"format":"relative-strokes","pages":[{"page":0,"background":"white","strokes":[]},{"page":0,"background":"white","strokes":[]}]}"#,
        #"{"format":"relative-strokes","pages":[{"page":0,"background":"white","strokes":[{"color":[0,0,0,1],"points":[0.1]}]}]}"#,
        #"{"format":"relative-strokes","pages":[{"page":0,"background":"white","strokes":[{"color":[0,0,0],"points":[]}]}]}"#,
        #"{"format":"relative-strokes","pages":[{"page":0,"background":"pink","strokes":[]}]}"#,
    ])
    func rejectsInvalidDrawings(_ json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CompanionDrawings.self, from: Data(json.utf8))
        }
    }

    // Damaged drawings make the file unreadable, so the next save cannot drop them.
    @Test func damagedDrawingsAreNotDropped() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: CompanionFileFormat.encode(entry(drawings: nil))) as? [String: Any])
        var inner = try #require(json["entry"] as? [String: Any])
        inner["drawings"] = ["format": "relative-strokes", "pages": 3]
        json["entry"] = inner
        #expect(throws: CompanionFileFormat.DecodingError.unreadable) {
            try CompanionFileFormat.decode(JSONSerialization.data(withJSONObject: json))
        }
    }

    // Files written before drawings were stored stay readable.
    @Test func drawingsAreOptional() throws {
        let decoded = try CompanionFileFormat.decode(CompanionFileFormat.encode(entry(drawings: nil)))
        #expect(decoded.entry.drawings == nil)
    }

    // ADR 0012: entries with drawings are user content and never expire.
    @Test func entriesWithDrawingsDoNotExpire() {
        let drawn = entry(drawings: CompanionDrawings(pages: [1: PageDrawing(strokes: [stroke()])]))
        #expect(drawn.holdsUserContent)
        #expect(drawn.hasStoredData)
        #expect(!drawn.isExpired(at: .distantFuture))
        #expect(entry(drawings: CompanionDrawings(pages: [:])).isExpired(at: .distantFuture))
    }
}

/// DRAW-07: the open document keeps its drawings in the companion entry.
@MainActor
@Suite
struct DocumentCompanionDrawingsTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "DocumentCompanionDrawingsTests-\(UUID().uuidString)")
    let locator = FakeLocator()

    private func makeCompanion() -> DocumentCompanion {
        DocumentCompanion(store: CompanionStore(directory: directory, locator: locator), saveDelay: .milliseconds(10))
    }

    private let drawings = CompanionDrawings(pages: [1: PageDrawing(strokes: [stroke()])])

    // Drawings are saved and found on the next open, without marking the document edited.
    @Test func drawingsAreSavedWithoutMarkingEdited() async {
        let url = locator.add("talk.pdf")
        let companion = makeCompanion()
        await companion.open(pdfAt: url, pageCount: 3)
        companion.setDrawings(drawings)
        #expect(!companion.isEdited)
        await companion.waitUntilSaved()

        let reopened = makeCompanion()
        await reopened.open(pdfAt: url, pageCount: 3)
        #expect(reopened.drawings == drawings)
    }

    // Empty drawings remove the stored ones.
    @Test func emptyDrawingsRemoveThem() async {
        let url = locator.add("talk.pdf")
        let companion = makeCompanion()
        await companion.open(pdfAt: url, pageCount: 3)
        companion.setDrawings(drawings)
        companion.setDrawings(CompanionDrawings(pages: [:]))
        #expect(companion.drawings == nil)
        companion.setDrawings(drawings)
        companion.setDrawings(nil)
        #expect(companion.drawings == nil)
    }

    // Before the entry is loaded there is nothing to store into.
    @Test func ignoredBeforeLoad() {
        let companion = makeCompanion()
        companion.setDrawings(drawings)
        #expect(companion.drawings == nil)
    }

    // DRAW-06: turning "Save drawings" off removes the drawings of every stored PDF and
    // keeps the rest of the entries.
    @Test func storeRemovesAllDrawings() async throws {
        let store = CompanionStore(directory: directory, locator: locator)
        var first = try #require(await store.open(pdfAt: locator.add("one.pdf"), pageCount: 3)).entry
        first.drawings = drawings
        first.notes = CompanionNotes(format: .rtf, pages: [Data([1])])
        await store.save(first)
        var second = try #require(await store.open(pdfAt: locator.add("two.pdf"), pageCount: 3)).entry
        second.settings.isNavigatorDisplayed = true
        await store.save(second)

        let changed = await store.removeAllDrawings()
        #expect(changed == [first.id])

        let reloaded = await CompanionStore(directory: directory, locator: locator).entries()
        #expect(reloaded.count == 2)
        #expect(reloaded.allSatisfy { $0.drawings == nil })
        #expect(reloaded.first { $0.id == first.id }?.notes == first.notes)
    }
}

/// DRAW-06, DRAW-07: the drawings in memory and the stored ones.
@MainActor
@Suite
struct StoredDrawingsModelTests {
    // Stored pages replace the pages in memory; pages drawn only in memory stay.
    @Test func loadingMergesStoredPages() {
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        drawings.startDrawing(onPage: 0)
        drawings.replaceStrokes([stroke(.green)], onPage: 0)
        drawings.replaceStrokes([stroke(.green)], onPage: 2)

        drawings.loadStoredPages([0: PageDrawing(strokes: [stroke(.orange)]), 4: PageDrawing(background: .white)])

        #expect(drawings.drawing(onPage: 0).strokes == [stroke(.orange)])
        #expect(drawings.drawing(onPage: 2).strokes == [stroke(.green)])
        #expect(drawings.drawing(onPage: 4).background == .white)
        // The replaced page's history would restore a drawing that was never stored.
        #expect(!drawings.canUndo(onPage: 0))
        #expect(drawings.canUndo(onPage: 2))
    }

    // Every change reports the pages, so the app can store them; equal pages report nothing.
    @Test func reportsChanges() {
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        var reported: [[Int: PageDrawing]] = []
        drawings.onPagesChange = { reported.append($0) }
        drawings.startDrawing(onPage: 1)
        drawings.replaceStrokes([stroke()], onPage: 1)
        drawings.undo(onPage: 1)
        drawings.loadStoredPages([:])
        #expect(reported == [[1: PageDrawing(strokes: [stroke()])], [:]])
    }

    // DRAW-06: turning "Save drawings" off deletes all drawings and their undo history.
    @Test func deleteAllRemovesEverything() {
        let drawings = DocumentDrawings()
        drawings.keepsDrawings = true
        drawings.startDrawing(onPage: 0)
        drawings.replaceStrokes([stroke()], onPage: 0)
        drawings.setBackground(.white, onPage: 3)
        drawings.beginLiveStroke(onPage: 0, at: [a])

        drawings.deleteAll()

        #expect(drawings.pages.isEmpty)
        #expect(drawings.liveStroke == nil)
        #expect(!drawings.canUndo(onPage: 0))
        #expect(drawings.isDrawing)
    }
}
