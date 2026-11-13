import PDFKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// PROTOTYPE (issue #10). Debug UI in English only, not localized. Never merged into main.

/// Shows the current page of the watched PDF and every change event.
struct ReloadProbeView: View {
    let document: ReloadProbeDocument
    @State private var session: ReloadProbeSession
    @State private var isShowingSelfTest = false

    init(url: URL, document: ReloadProbeDocument) {
        self.document = document
        _session = State(initialValue: ReloadProbeSession(url: url, data: document.data))
    }

    var body: some View {
        // One column on every platform: a split view collapses to the event list on iPhone
        // and hides the page.
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                PageImage(page: session.document?.page(at: session.currentPage))
                    .frame(maxHeight: 360)
                HStack {
                    Button {
                        session.showPage(session.currentPage - 1)
                    } label: {
                        Label { Text(verbatim: "Previous Page") } icon: { Image(systemName: "chevron.left") }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    Text(verbatim: "Page \(session.currentPage + 1) of \(session.pageCount)")
                        .monospacedDigit()
                    Button {
                        session.showPage(session.currentPage + 1)
                    } label: {
                        Label { Text(verbatim: "Next Page") } icon: { Image(systemName: "chevron.right") }
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .labelStyle(.iconOnly)
                Text(verbatim: "Reloads: \(session.reloadCount) · DocumentGroup deliveries: \(session.documentGroupDeliveries)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            List {
                Section {
                    ForEach(session.log.reversed()) { entry in
                        LabeledContent {
                            Text(verbatim: "\(entry.milliseconds) ms").monospacedDigit()
                        } label: {
                            Text(verbatim: entry.text)
                        }
                    }
                } header: {
                    Text(verbatim: "Events (newest first)")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await session.runSelfTest()
                        isShowingSelfTest = true
                    }
                } label: {
                    Label { Text(verbatim: "Run Self-Test") } icon: { Image(systemName: "stethoscope") }
                }
                .disabled(session.isRunningSelfTest)
                Button {
                    copyToPasteboard(session.report)
                } label: {
                    Label { Text(verbatim: "Copy Report") } icon: { Image(systemName: "doc.on.doc") }
                }
            }
        }
        .overlay {
            if session.isRunningSelfTest {
                ProgressView { Text(verbatim: "Running self-test (about 40 s)…") }
            }
        }
        .sheet(isPresented: $isShowingSelfTest) {
            NavigationStack {
                ScrollView {
                    Text(verbatim: session.selfTestReport ?? "")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { isShowingSelfTest = false } label: { Text(verbatim: "Done") }
                    }
                }
            }
            .frame(minWidth: Self.sheetMinimumSize?.width, minHeight: Self.sheetMinimumSize?.height)
        }
        .task { session.start(initialData: document.data) }
        .onDisappear { session.stop() }
        .onChange(of: document.digest) {
            session.documentGroupDelivered(digest: document.digest, byteCount: document.data.count)
        }
    }

    /// Mac sheets need a size; on iOS the sheet fills the screen (an iPhone is narrower than 500 pt).
    private static var sheetMinimumSize: CGSize? {
        #if os(macOS)
        CGSize(width: 500, height: 400)
        #else
        nil
        #endif
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

private struct PageImage: View {
    let page: PDFPage?

    var body: some View {
        if let page {
            image(of: page)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(Text(verbatim: "Current page"))
        } else {
            ContentUnavailableView {
                Label { Text(verbatim: "No Page") } icon: { Image(systemName: "doc") }
            }
        }
    }

    private func image(of page: PDFPage) -> Image {
        let size = CGSize(width: 1200, height: 900)
        #if os(macOS)
        return Image(nsImage: page.thumbnail(of: size, for: .mediaBox))
        #else
        return Image(uiImage: page.thumbnail(of: size, for: .mediaBox))
        #endif
    }
}
