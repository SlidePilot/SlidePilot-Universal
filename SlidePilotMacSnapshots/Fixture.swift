import Foundation

/// The repository's `Fixtures/` folder, copied into this test bundle.
///
/// The snapshots run inside the App-Sandboxed app, which cannot read the repository
/// folder, so the fixtures travel with the bundle as a folder reference.
enum Fixture {
    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "Fixtures/\(name) is not in the test bundle" }
    }

    /// The contents of `Fixtures/<name>`, e.g. `Fixture.data("plain-slides.pdf")`.
    static func data(_ name: String) throws -> Data {
        let url = Bundle(for: BundleToken.self).resourceURL?
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .notDirectory)
        guard let url, let data = try? Data(contentsOf: url) else { throw Missing(name: name) }
        return data
    }

    private final class BundleToken {}
}
