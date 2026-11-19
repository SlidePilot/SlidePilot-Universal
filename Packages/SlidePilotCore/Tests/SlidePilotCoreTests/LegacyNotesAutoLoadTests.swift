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

    // A declined or failed file is skipped even with a grant, so it never asks or fails on every open.
    @Test func skipsADeclinedFileEvenWithAGrant() {
        #expect(LegacyNotesAutoLoad.action(notesFile: file, hasNotes: false, declined: true, grantedFolder: folder) == .none)
    }

    // NOTES-10: notes in the companion file are never replaced by the old file.
    @Test func storedNotesWin() {
        #expect(LegacyNotesAutoLoad.action(notesFile: file, hasNotes: true, declined: false, grantedFolder: folder) == .none)
    }
}
