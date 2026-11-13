import Foundation
import Observation
import PDFKit

// PROTOTYPE (issue #7) – never merged into main.
// One session for the whole app. Production uses one PresentationSession per
// document (issue #13); the external-display scene then needs an app-level
// registry to find the session that is presenting.

/// Shared state of the presenter and the presentation surface.
@Observable
final class PrototypeSession {
    /// Reachable from the UIKit scene delegate on iPad, which SwiftUI cannot inject into.
    /// Prototype shortcut: production must not use a global for document state.
    static let shared = PrototypeSession()

    private(set) var document: PDFDocument?
    /// Bumped on every successful open, so views can react to "a new document was opened".
    private(set) var documentGeneration = 0
    var pageIndex = 0
    var showTestPattern = false

    /// Number of connected external-display scenes (iPad only).
    var externalDisplayScenes = 0

    private(set) var log: [LogEntry] = []
    private let start = ContinuousClock.now
    private var scopedURL: URL?

    struct LogEntry: Identifiable {
        let id = UUID()
        let seconds: Double
        let text: String

        var formatted: String {
            String(format: "[%7.2fs] ", seconds) + text
        }
    }

    var pageCount: Int { document?.pageCount ?? 0 }

    func page(at index: Int) -> PDFPage? {
        guard let document, index >= 0, index < document.pageCount else { return nil }
        return document.page(at: index)
    }

    // MARK: Opening

    func open(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        guard let document = PDFDocument(url: url) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            record("open failed: not a readable PDF")
            return
        }
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        install(document)
    }

    func openSample() {
        guard let url = Bundle.main.url(forResource: "prototype-sample", withExtension: "pdf"),
              let document = PDFDocument(url: url)
        else {
            record("open sample failed: resource missing")
            return
        }
        install(document)
    }

    private func install(_ document: PDFDocument) {
        self.document = document
        pageIndex = 0
        documentGeneration += 1
        // No file names or titles in the log: Pascal pastes it into chat and private decks stay private.
        let size = document.page(at: 0)?.bounds(for: .cropBox).size ?? .zero
        record("document opened: \(document.pageCount) pages, first page \(Int(size.width))×\(Int(size.height)) pt")
    }

    // MARK: Navigation

    func next() {
        guard pageIndex + 1 < pageCount else { return }
        pageIndex += 1
    }

    func previous() {
        guard pageIndex > 0 else { return }
        pageIndex -= 1
    }

    // MARK: Log

    func record(_ text: String) {
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        log.append(LogEntry(seconds: seconds, text: text))
    }

    func clearLog() {
        log.removeAll()
    }

    var logText: String {
        log.map(\.formatted).joined(separator: "\n")
    }
}
