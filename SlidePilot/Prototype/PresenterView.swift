import SwiftUI
import UniformTypeIdentifiers

// PROTOTYPE (issue #7). Debug UI in English only, not localized.

/// Presenter: current and next slide, navigation, and a diagnostics inspector.
struct PresenterView: View {
    let session: PrototypeSession

    @State private var isImporting = false
    @State private var showsDiagnostics = true

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: "SlidePilot Prototype"))
                .toolbar { toolbar }
        }
        .inspector(isPresented: $showsDiagnostics) {
            DiagnosticsView(session: session)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): session.open(url: url)
                case .failure: session.record("open cancelled or failed")
                }
            }
            .modifier(PresenterPlatformModifier(session: session))
            .task {
                // Launch argument `-prototypeOpenSample YES` opens the sample (screenshots, quick checks).
                if UserDefaults.standard.bool(forKey: "prototypeOpenSample"), session.document == nil {
                    session.openSample()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if session.document == nil {
            ContentUnavailableView {
                Label {
                    Text(verbatim: "No Presentation Open")
                } icon: {
                    Image(systemName: "rectangle.on.rectangle")
                }
            } description: {
                Text(verbatim: "Open a PDF or the built-in sample to test the presentation display.")
            } actions: {
                Button { isImporting = true } label: { Text(verbatim: "Open PDF…") }
                    .buttonStyle(.borderedProminent)
                Button { session.openSample() } label: { Text(verbatim: "Open Sample") }
            }
        } else {
            slides
        }
    }

    private var slides: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text(verbatim: "Current – \(session.pageIndex + 1) / \(session.pageCount)")
                    .font(.headline)
                SlideImageView(session: session, pageIndex: session.pageIndex)
                    .accessibilityLabel(Text(verbatim: "Current slide \(session.pageIndex + 1)"))
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading) {
                Text(verbatim: session.pageIndex + 1 < session.pageCount ? "Next" : "End of presentation")
                    .font(.headline)
                SlideImageView(session: session, pageIndex: session.pageIndex + 1)
                    .accessibilityLabel(Text(verbatim: "Next slide"))
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { isImporting = true } label: {
                Label { Text(verbatim: "Open PDF") } icon: { Image(systemName: "doc") }
            }
            Button { session.previous() } label: {
                Label { Text(verbatim: "Previous Slide") } icon: { Image(systemName: "chevron.left") }
            }
            .disabled(session.pageIndex == 0)
            Button { session.next() } label: {
                Label { Text(verbatim: "Next Slide") } icon: { Image(systemName: "chevron.right") }
            }
            .disabled(session.pageIndex + 1 >= session.pageCount)
            Toggle(isOn: Bindable(session).showTestPattern) {
                Label { Text(verbatim: "Test Pattern") } icon: { Image(systemName: "squareshape.split.3x3") }
            }
            Button { showsDiagnostics.toggle() } label: {
                Label { Text(verbatim: "Diagnostics") } icon: { Image(systemName: "sidebar.trailing") }
            }
        }
    }
}

/// Display state and event log. Platform-specific rows come from `PlatformDiagnostics`.
struct DiagnosticsView: View {
    let session: PrototypeSession

    var body: some View {
        Form {
            PlatformDiagnostics(session: session)
            Section {
                Button { copyToPasteboard(session.logText) } label: {
                    Label { Text(verbatim: "Copy Log") } icon: { Image(systemName: "doc.on.doc") }
                }
                Button(role: .destructive) { session.clearLog() } label: {
                    Label { Text(verbatim: "Clear Log") } icon: { Image(systemName: "trash") }
                }
                ForEach(session.log.reversed()) { entry in
                    Text(verbatim: entry.formatted)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text(verbatim: "Event Log (newest first)")
            }
        }
        .formStyle(.grouped)
    }
}

/// Keyboard navigation for every window, including the presentation window.
struct PrototypeCommands: Commands {
    let session: PrototypeSession

    var body: some Commands {
        CommandMenu(Text(verbatim: "Slides")) {
            Button { session.next() } label: { Text(verbatim: "Next Slide") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button { session.next() } label: { Text(verbatim: "Next Slide (Space)") }
                .keyboardShortcut(.space, modifiers: [])
            Button { session.previous() } label: { Text(verbatim: "Previous Slide") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Divider()
            Button { session.showTestPattern.toggle() } label: { Text(verbatim: "Toggle Test Pattern") }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}
