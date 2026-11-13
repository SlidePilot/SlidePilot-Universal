import CoreGraphics
import Foundation
import Testing
@testable import SlidePilotRendering

@Suite struct PDFInspectorTests {
    @Test func readsPageCountOfAValidPDF() throws {
        let info = try PDFInspector.inspect(TestPDF.make(pages: 6))
        #expect(info.pageCount == 6)
        #expect(info.pageSizes.allSatisfy { $0 == TestPDF.pageSize })
    }

    @Test func reportsPageSizesInTheirDisplayedOrientation() throws {
        let data = try TestPDF.rotating(TestPDF.make(pages: 4), by: [0, 90, 180, 270])
        let info = try PDFInspector.inspect(data)
        let portrait = CGSize(width: TestPDF.pageSize.height, height: TestPDF.pageSize.width)
        #expect(info.pageSizes == [TestPDF.pageSize, portrait, TestPDF.pageSize, portrait])
    }

    @Test func acceptsASinglePage() throws {
        let info = try PDFInspector.inspect(TestPDF.make(pages: 1))
        #expect(info.pageCount == 1)
    }

    // DEF-17: the old app failed silently on unreadable files; the new app reports a reason.
    @Test func rejectsEmptyData() {
        #expect(throws: PDFOpenError.notAPDF) {
            try PDFInspector.inspect(Data())
        }
    }

    @Test func rejectsDataThatIsNotAPDF() {
        #expect(throws: PDFOpenError.notAPDF) {
            try PDFInspector.inspect(Data("This is plain text, not a PDF.".utf8))
        }
    }

    @Test func rejectsAPDFWithoutPages() throws {
        // Core Graphics and PDFKit never write a page-less PDF, so build a minimal one by hand.
        let data = Data("""
            %PDF-1.4
            1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
            2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj
            trailer << /Root 1 0 R >>
            %%EOF
            """.utf8)
        let error = #expect(throws: PDFOpenError.self) {
            try PDFInspector.inspect(data)
        }
        // PDFKit may refuse to parse a page-less file at all; both reasons are reported to the user.
        #expect(error == .noPages || error == .notAPDF)
    }

    @Test func rejectsAPasswordProtectedPDF() {
        #expect(throws: PDFOpenError.locked) {
            try PDFInspector.inspect(TestPDF.make(pages: 2, userPassword: "secret"))
        }
    }

    // An owner password only restricts printing or copying; the slides can still be shown.
    @Test func acceptsAPDFWithOnlyAnOwnerPassword() throws {
        let info = try PDFInspector.inspect(TestPDF.make(pages: 3, ownerPassword: "owner"))
        #expect(info.pageCount == 3)
    }
}
