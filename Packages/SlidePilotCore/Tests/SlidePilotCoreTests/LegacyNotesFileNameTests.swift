import Foundation
import Testing
@testable import SlidePilotCore

@Suite struct LegacyNotesFileNameTests {
    @Test func candidatesFollowTheOldSearchOrder() {
        #expect(LegacyNotesFileName.candidates(forPDFBaseName: "talk") == [
            "talk-Notes.rtf", "talk-notes.rtf", "talk-Notizen.rtf",
            "talk_Notes.rtf", "talk_notes.rtf", "talk_Notizen.rtf",
            "talk Notes.rtf", "talk notes.rtf", "talk Notizen.rtf",
        ])
    }

    @Test func candidateURLsAreNextToThePDF() {
        let pdf = URL(filePath: "/Talks/My talk.v2.pdf")
        let urls = LegacyNotesFileName.candidates(forPDFAt: pdf)
        #expect(urls.count == 9)
        #expect(urls.allSatisfy { $0.deletingLastPathComponent().path == "/Talks" })
        #expect(urls.first?.lastPathComponent == "My talk.v2-Notes.rtf")
    }

    @Test func firstMatchWins() {
        let pdf = URL(filePath: "/Talks/links.pdf")
        let existing: Set<String> = ["links_Notizen.rtf", "links notes.rtf"]
        let match = LegacyNotesFileName.firstExisting(forPDFAt: pdf) { existing.contains($0.lastPathComponent) }
        #expect(match?.lastPathComponent == "links_Notizen.rtf")
    }

    // Case-sensitive volumes (iOS): only the exact spelling exists, so every spelling is tried.
    @Test func findsLowercaseNameOnCaseSensitiveVolumes() {
        let pdf = URL(filePath: "/Talks/plain-slides.pdf")
        let match = LegacyNotesFileName.firstExisting(forPDFAt: pdf) {
            $0.lastPathComponent == "plain-slides-notes.rtf"
        }
        #expect(match?.lastPathComponent == "plain-slides-notes.rtf")
    }

    @Test func noMatchGivesNil() {
        let pdf = URL(filePath: "/Talks/links.pdf")
        #expect(LegacyNotesFileName.firstExisting(forPDFAt: pdf) { _ in false } == nil)
    }

    @Test func exportNameUsesThePDFNameAndLocalizedWord() {
        #expect(LegacyNotesFileName.exportName(forPDFBaseName: "talk", localizedNotes: "Notizen") == "talk-Notizen.rtf")
        #expect(LegacyNotesFileName.exportName(forPDFBaseName: nil, localizedNotes: "Notizen") == "Notes.rtf")
        #expect(LegacyNotesFileName.exportName(forPDFBaseName: "", localizedNotes: "Notizen") == "Notes.rtf")
    }
}
