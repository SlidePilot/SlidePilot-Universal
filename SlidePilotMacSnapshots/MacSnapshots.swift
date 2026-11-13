import CoreGraphics
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
    func firstSlide(appearance: WindowSnapshot.Appearance) async throws {
        let document = try PDFFileDocument(data: Fixture.data("plain-slides.pdf"))
        try await WindowSnapshot.record(DocumentView(document: document), name: "slides-first", appearance: appearance)
    }

    // LAY-09: after the last slide the preview shows the end-of-deck page.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func lastSlide(appearance: WindowSnapshot.Appearance) async throws {
        let data = try Fixture.data("plain-slides.pdf")
        let pdf = try #require(PDFDocument(data: data))
        let document = try PDFFileDocument(data: data)
        let view = DocumentView(document: document, page: pdf.pageCount - 1)
        try await WindowSnapshot.record(view, name: "slides-last", appearance: appearance)
    }

    // PROTOTYPE (issue #7): presenter with the bundled fixture, and the presentation surface.
    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func prototypePresenter(appearance: WindowSnapshot.Appearance) async throws {
        let session = PrototypeSession()
        session.openSample()
        try await WindowSnapshot.record(
            PresenterView(session: session), name: "prototype-presenter",
            size: CGSize(width: 1200, height: 700), appearance: appearance
        )
    }

    @Test(arguments: WindowSnapshot.Appearance.allCases)
    func prototypePresentation(appearance: WindowSnapshot.Appearance) async throws {
        let session = PrototypeSession()
        session.openSample()
        session.pageIndex = 1
        try await WindowSnapshot.record(
            PresentationView(session: session, host: "snapshot"), name: "prototype-presentation",
            size: CGSize(width: 960, height: 540), appearance: appearance
        )
    }
}
