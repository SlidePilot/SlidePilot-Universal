import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// PROTOTYPE (issue #9). Debug UI in English only, not localized. Never merged into main.

/// Shows the probe results for one opened PDF.
struct ProbeView: View {
    @State private var session: ProbeSession
    @State private var isPickingFolder = false

    init(pdfURL: URL, deliveredByteCount: Int) {
        _session = State(initialValue: ProbeSession(pdfURL: pdfURL, deliveredByteCount: deliveredByteCount))
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: "Grant folder access to repeat the probes with the PDF's folder. "
                    + "Relaunch the app and use Check Stored Bookmarks to test bookmarks.")
                    .foregroundStyle(.secondary)
            }
            ForEach(session.runs) { run in
                Section {
                    ForEach(run.results) { ResultRow(result: $0) }
                } header: {
                    Text(verbatim: run.context.rawValue)
                }
            }
            if !session.bookmarkChecks.isEmpty {
                Section {
                    ForEach(session.bookmarkChecks) { ResultRow(result: $0) }
                } header: {
                    Text(verbatim: "Stored bookmarks")
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if session.isRunning { ProgressView() }
        }
        .toolbar { toolbar }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await session.grantFolder(url) }
            }
        }
        .fileDialogDefaultDirectory(session.folderURL)
        .task { await session.start() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                isPickingFolder = true
            } label: {
                Label { Text(verbatim: "Grant Folder Access…") } icon: { Image(systemName: "folder.badge.plus") }
            }
            Button {
                session.checkStoredBookmarks()
            } label: {
                Label { Text(verbatim: "Check Stored Bookmarks") } icon: { Image(systemName: "bookmark") }
            }
            Button {
                copyToPasteboard(session.report)
            } label: {
                Label { Text(verbatim: "Copy Report") } icon: { Image(systemName: "doc.on.doc") }
            }
            Menu {
                Button(role: .destructive) {
                    session.clearStoredGrants()
                } label: {
                    Text(verbatim: "Clear Stored Bookmarks")
                }
            } label: {
                Label { Text(verbatim: "More") } icon: { Image(systemName: "ellipsis") }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

private struct ResultRow: View {
    let result: ProbeResult

    var body: some View {
        LabeledContent {
            Text(verbatim: result.detail)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Label {
                Text(verbatim: result.name)
            } icon: {
                icon
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch result.outcome {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel(Text(verbatim: "OK"))
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                .accessibilityLabel(Text(verbatim: "Failed"))
        case .notApplicable:
            Image(systemName: "info.circle").foregroundStyle(.secondary)
                .accessibilityLabel(Text(verbatim: "Info"))
        }
    }
}
