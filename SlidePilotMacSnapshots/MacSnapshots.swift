import PDFKit
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
    func openedDocument(appearance: WindowSnapshot.Appearance) async throws {
        let pdf = try #require(PDFDocument(data: Fixture.data("plain-slides.pdf")))
        let view = DocumentView(title: "plain-slides", pageCount: pdf.pageCount)
        try await WindowSnapshot.record(view, name: "document-opened", appearance: appearance)
    }
}
