import Foundation
import Testing
@testable import SlidePilotCore

@Suite struct LegacyNotesAutoLoadTests {
    let file = URL(filePath: "/Talks/talk-Notes.rtf")
    let folder = URL(filePath: "/Talks")

    @Test func noFileDoesNothing() {
        #expect(LegacyNotesAutoLoad.action(notesFile: nil, hasNotes: false, declined: false, grantedFolder: folder) == .none)
    }

    // NOTES-08: with a folder grant the file loads without asking.
    @Test func loadsWithAGrant() {
        #expect(LegacyNotesAutoLoad.action(notesFile: file, hasNotes: false, declined: false, grantedFolder: folder)
            == .load(file: file, folder: folder))
    }

    // ADR 0012: without a grant the app asks for the folder once.
    @Test func asksWithoutAGrant() {
        #expect(LegacyNotesAutoLoad.action(notesFile: file, hasNotes: false, declined: false, grantedFolder: nil)
            == .askForFolder(file: file))
    }

    @Test func doesNotAskAgainAfterADecline() {
        #expect(LegacyNotesAutoLoad.action(notesFile: file, hasNotes: false, declined: true, grantedFolder: nil) == .none)
    }

    // A grant given later (e.g. for another PDF in the folder) still loads.
    @Test func loadsAfterADeclineOnceGranted() {
        #expect(LegacyNotesAutoLoad.action(notesFile: file, hasNotes: false, declined: true, grantedFolder: folder)
            == .load(file: file, folder: folder))
    }

    // NOTES-10: notes in the companion file are never replaced by the old file.
    @Test func storedNotesWin() {
        #expect(LegacyNotesAutoLoad.action(notesFile: file, hasNotes: true, declined: false, grantedFolder: folder) == .none)
    }
}
