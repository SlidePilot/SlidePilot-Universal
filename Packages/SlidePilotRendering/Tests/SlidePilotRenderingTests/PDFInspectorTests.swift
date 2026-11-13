import CoreGraphics
import Foundation
import Testing
@testable import SlidePilotRendering

@Suite struct PDFInspectorTests {
    @Test func readsPageCountOfAValidPDF() throws {
        let info = try PDFInspector.inspect(TestPDF.make(pages: 6))
        #expect(info == PDFDocumentInfo(pageCount: 6))
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

/// Builds small PDFs in memory, so the tests need no files on disk.
enum TestPDF {
    static func make(pages: Int, userPassword: String? = nil, ownerPassword: String? = nil) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 362.8, height: 272.1)
        var info: [CFString: Any] = [:]
        if let userPassword {
            info[kCGPDFContextUserPassword] = userPassword
            info[kCGPDFContextOwnerPassword] = ownerPassword ?? userPassword
        } else if let ownerPassword {
            info[kCGPDFContextOwnerPassword] = ownerPassword
            info[kCGPDFContextAllowsCopying] = false
        }
        guard
            let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return Data() }
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 20, y: 20, width: 100, height: 60))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
