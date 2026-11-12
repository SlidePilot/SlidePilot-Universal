import Foundation
import Testing
@testable import SlidePilot

// PROTOTYPE (issue #10): runs the auto-reload scenarios inside the sandboxed app. Never merged into main.

@Suite
struct ReloadSelfTest {
    @Test(.timeLimit(.minutes(3)))
    func writePatternsInSandboxedApp() async throws {
        let report = await ReloadProbeSession.selfTest()
        Attachment.record(report, named: "reload-self-test.md")
        // The result bundle compresses text attachments, so also print the report into the test log.
        print("=== reload self-test ===\n\(report)\n=== end ===")
    }
}
