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
    func emptyState(appearance: WindowSnapshot.Appearance) async throws {
        try await WindowSnapshot.record(ContentView(), name: "empty-state", appearance: appearance)
    }
}
