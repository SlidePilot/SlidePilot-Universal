import Foundation
import SlidePilotCore
@testable import SlidePilotRendering
import Testing
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

@Suite
struct CompanionNotesRTFTests {
    // NOTES-10: formatted notes survive the companion format, page by page.
    @Test func keepsTextAndFormattingPerPage() throws {
        #if canImport(AppKit)
        let bold = NSFont.boldSystemFont(ofSize: 20)
        #else
        let bold = UIFont.boldSystemFont(ofSize: 20)
        #endif
        let first = try AttributedString(NSAttributedString(string: "Bold", attributes: [.font: bold]), including: \.platformScope)
        let pages = [first, AttributedString(), AttributedString("Plain")]
        let notes = try CompanionNotesRTF.notes(fromPages: pages)
        #expect(notes.format == .rtf)
        #expect(notes.pages[1].isEmpty)

        let decoded = try CompanionNotesRTF.pages(from: notes)
        #expect(decoded.map { String($0.characters) } == ["Bold", "", "Plain"])
        let font = try #require(NSAttributedString(decoded[0], including: \.platformScope).attribute(.font, at: 0, effectiveRange: nil))
        #if canImport(AppKit)
        let decodedFont = try #require(font as? NSFont)
        #expect(decodedFont.fontDescriptor.symbolicTraits.contains(.bold))
        #else
        let decodedFont = try #require(font as? UIFont)
        #expect(decodedFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        #endif
        #expect(decodedFont.pointSize == 20)
    }

    @Test func rejectsUnknownFormats() {
        let notes = CompanionNotes(format: CompanionNotes.Format(rawValue: "future"), pages: [Data([1])])
        #expect(throws: LegacyNotesRTFError.unreadable) {
            try CompanionNotesRTF.pages(from: notes)
        }
    }
}

#if canImport(AppKit)
private extension AttributeScopes {
    var platformScope: AppKitAttributes.Type { AppKitAttributes.self }
}
#else
private extension AttributeScopes {
    var platformScope: UIKitAttributes.Type { UIKitAttributes.self }
}
#endif
