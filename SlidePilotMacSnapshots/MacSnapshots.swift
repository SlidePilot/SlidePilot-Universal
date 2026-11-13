import AppKit
import Testing
@testable import SlidePilot

/// Mac screenshots for PRs, rendered by the app itself (see `WindowSnapshot`).
///
/// Not part of the default test plan. Run the `SlidePilotMacSnapshots` scheme and
/// export the PNGs with `scripts/export-mac-snapshots.py`.
/// Use fixtures only, never personal documents.
@Suite(.serialized)
struct MacSnapshots {
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func firstSlide(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: SnapshotDeck.make(pages: 3))
        try await WindowSnapshot.record(DocumentView(document: document), name: "slides-first", appearance: appearance)
    }

    // LAY-09: after the last slide the preview shows the end-of-deck page.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func lastSlide(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: SnapshotDeck.make(pages: 3))
        let view = DocumentView(document: document, page: 2)
        try await WindowSnapshot.record(view, name: "slides-last", appearance: appearance)
    }
}

/// A small generated deck, so the snapshots need no files outside the app sandbox.
enum SnapshotDeck {
    static func make(pages: Int) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 362.8, height: 272.1)
        guard
            let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }
        for page in 1...pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor(srgbRed: 0.2, green: 0.25, blue: 0.5, alpha: 1).setFill()
            CGRect(x: 0, y: 232, width: mediaBox.width, height: 40.1).fill()
            let title = NSAttributedString(string: "Slide \(page)", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor.white,
            ])
            title.draw(at: CGPoint(x: 16, y: 242))
            let body = NSAttributedString(string: "• Point one\n• Point two", attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.black,
            ])
            body.draw(at: CGPoint(x: 24, y: 150))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
