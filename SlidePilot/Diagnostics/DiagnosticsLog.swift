import OSLog
import SwiftUI

// TEMPORARY (hardware tests for #13): an in-app event log for devices that cannot be
// attached to the Xcode console. Remove this folder and its uses before the PR is merged.

/// Recent screen and scene events, shown by `DiagnosticsButton`.
@MainActor
@Observable
final class DiagnosticsLog {
    /// Temporary and holds no document state; a global keeps the test code out of the
    /// scene and delegate initializers.
    static let shared = DiagnosticsLog()

    private(set) var entries: [String] = []
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SlidePilot",
        category: "Diagnostics"
    )

    func record(_ text: String) {
        let time = Date.now.formatted(.dateTime.hour().minute().second())
        entries.append("\(time) \(text)")
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
        logger.notice("\(text, privacy: .public)")
    }

    func clear() {
        entries.removeAll()
    }
}

/// Toolbar button that shows the diagnostics log with copy and share.
struct DiagnosticsButton: View {
    @State private var isShown = false

    var body: some View {
        Button {
            isShown = true
        } label: {
            Label {
                Text(verbatim: "Diagnostics")
            } icon: {
                Image(systemName: "ladybug")
            }
        }
        .sheet(isPresented: $isShown) {
            DiagnosticsView()
        }
    }
}

private struct DiagnosticsView: View {
    private let log = DiagnosticsLog.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(log.entries.enumerated().reversed()), id: \.offset) { _, entry in
                Text(verbatim: entry)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            .navigationTitle(Text(verbatim: "Diagnostics"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: "Done")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: log.entries.joined(separator: "\n")) {
                        Label {
                            Text(verbatim: "Share Log")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button {
                        log.clear()
                    } label: {
                        Text(verbatim: "Clear")
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
