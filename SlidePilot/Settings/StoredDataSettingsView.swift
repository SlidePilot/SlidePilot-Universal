import SlidePilotCore
import SwiftUI

/// The General pane's link to the stored data overview (SET-07): a sheet on the Mac, like
/// Trusted Devices, a page of the settings sheet on iPad.
struct StoredDataSection: View {
    #if os(macOS)
    @State private var isShowingStoredData = false
    #endif

    var body: some View {
        Section {
            #if os(macOS)
            Button("Stored Document Data…") {
                isShowingStoredData = true
            }
            .sheet(isPresented: $isShowingStoredData) {
                NavigationStack {
                    StoredDataList()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingStoredData = false }
                            }
                        }
                }
                .frame(minWidth: 480, minHeight: 360)
                .onExitCommand { isShowingStoredData = false }
            }
            #else
            // A value link: the sheet's stack has a typed path (`SettingsView`).
            NavigationLink(value: SettingsTab.storedData) {
                Label("Stored Document Data", systemImage: "externaldrive")
            }
            #endif
        } footer: {
            Text("Notes, drawings and settings of your PDFs stay stored when a PDF is deleted. Review and delete them here.")
        }
    }
}

/// The stored data overview (SET-07): one row per companion entry, deleting single entries,
/// the selection or all entries whose PDF is not found, each after a confirmation. Nothing
/// is deleted automatically.
struct StoredDataList: View {
    /// What the confirmation dialog asks to delete.
    private enum Deletion: Equatable {
        case items(Set<UUID>)
        case notFound
    }

    /// The open documents, so their windows drop deleted data too.
    @Environment(OpenCompanions.self) private var openCompanions: OpenCompanions?
    @State private var overview: StoredDataOverview?
    @State private var selection = Set<UUID>()
    @State private var deletion: Deletion?
    #if os(macOS)
    /// The entry being exported as a `.slidepilot` file (NOTES-11).
    @State private var export: (document: SlidePilotFileDocument, name: String)?
    @State private var exportFailure: String?
    #endif
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif

    private var showsDeleteSelection: Bool {
        #if os(macOS)
        true
        #else
        editMode?.wrappedValue.isEditing == true
        #endif
    }

    var body: some View {
        List(selection: $selection) {
            if let items = overview?.items, !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        StoredDataRow(item: item)
                            .contextMenu {
                                exportButton(for: item)
                                Button("Delete…", systemImage: "trash", role: .destructive) {
                                    deletion = .items(selection.contains(item.id) ? selection : [item.id])
                                }
                            }
                    }
                    .onDelete { offsets in
                        deletion = .items(Set(offsets.map { items[$0].id }))
                    }
                } footer: {
                    #if os(iOS)
                    exportHint
                    #endif
                }
            }
        }
        #if os(macOS)
        // Below the list: a Mac list cuts its section footers off after one line.
        .safeAreaInset(edge: .bottom) {
            if overview?.items?.isEmpty == false {
                exportHint
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
        #endif
        .overlay {
            if overview?.items?.isEmpty == true {
                ContentUnavailableView(
                    "No Stored Data",
                    systemImage: "doc.text",
                    description: Text("Notes, drawings and settings of the PDFs you open appear here.")
                )
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            if !selection.isEmpty {
                deletion = .items(selection)
            }
        }
        #else
        // The Delete key with a hardware keyboard.
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard !selection.isEmpty else { return .ignored }
            deletion = .items(selection)
            return .handled
        }
        #endif
        .navigationTitle("Stored Document Data")
        .toolbar {
            // In the sheet's button row on the Mac; in the bottom bar on iPad, where the
            // navigation bar is too narrow for it next to the title.
            ToolbarItemGroup(placement: deleteNotFoundPlacement) {
                // A visible way to delete the selection; on iPad while editing.
                if showsDeleteSelection {
                    Button("Delete…", role: .destructive) {
                        deletion = .items(selection)
                    }
                    .disabled(selection.isEmpty)
                }
                Button("Delete Not Found…", role: .destructive) {
                    deletion = .notFound
                }
                .disabled(overview?.notFoundItems.isEmpty ?? true)
            }
            #if os(iOS)
            if overview?.items?.isEmpty == false {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            #endif
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: $deletion.isPresented,
            titleVisibility: .visible,
            presenting: deletion
        ) { deletion in
            Button("Delete", role: .destructive) {
                delete(deletion)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deletion in
            switch deletion {
            case .items:
                Text("The notes, drawings and settings that SlidePilot stores are deleted. This can’t be undone.")
            case .notFound:
                Text("These PDFs may have been deleted, or they are on a drive that isn’t connected or in iCloud and not downloaded. Their notes, drawings and settings are deleted. This can’t be undone.")
            }
        }
        #if os(macOS)
        .fileExporter(
            isPresented: $export.isPresented,
            document: export?.document,
            contentType: .slidePilotFile,
            defaultFilename: export?.name
        ) { result in
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                exportFailure = error.localizedDescription
            }
        }
        .alert(
            Text("The SlidePilot File Couldn’t Be Exported"),
            isPresented: $exportFailure.isPresented,
            presenting: exportFailure
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        #endif
        .task {
            if overview == nil {
                overview = StoredDataOverview(store: .app) { [openCompanions] in openCompanions?.all ?? [] }
            }
            await overview?.reload()
        }
    }

    private var exportHint: Text {
        Text("To keep the notes, drawings and settings of a PDF, choose Export… in its context menu before deleting its data.")
    }

    /// Exports the entry as a `.slidepilot` file (NOTES-11): a save panel on the Mac, the
    /// share sheet on iPad.
    @ViewBuilder
    private func exportButton(for item: StoredDataItem) -> some View {
        let name = SlidePilotFile.exportName(forPDFNamed: item.fileName)
        #if os(macOS)
        Button("Export…", systemImage: SlidePilotFileCommands.exportSymbol) {
            Task {
                guard let file = await overview?.exportFile(for: item.id) else { return }
                export = (SlidePilotFileDocument(file: file), name)
            }
        }
        #else
        if let overview {
            ShareLink(item: SlidePilotFileExport(fileName: name) { await overview.exportFile(for: item.id) }, preview: SharePreview(name)) {
                Label("Export…", systemImage: SlidePilotFileCommands.exportSymbol)
            }
        }
        #endif
    }

    private var deleteNotFoundPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .destructiveAction
        #else
        .bottomBar
        #endif
    }

    private var dialogTitle: Text {
        switch deletion {
        case .items(let ids) where ids.count == 1:
            let name = overview?.items?.first { ids.contains($0.id) }?.displayName ?? ""
            return Text("Delete the Data of “\(name)”?")
        case .items:
            return Text("Delete the Data of the Selected PDFs?")
        case .notFound:
            let count = overview?.notFoundItems.count ?? 0
            return Text("Delete the Data of \(count) PDFs Not Found?")
        case nil:
            return Text(verbatim: "")
        }
    }

    private func delete(_ deletion: Deletion) {
        guard let overview else { return }
        let ids = switch deletion {
        case .items(let ids): ids
        case .notFound: Set(overview.notFoundItems.map(\.id))
        }
        selection.subtract(ids)
        Task { await overview.delete(ids) }
    }
}

/// One entry: PDF name, what it holds, last opened, size and whether the PDF is found.
private struct StoredDataRow: View {
    let item: StoredDataItem

    var body: some View {
        LabeledContent {
            Text(item.byteCount, format: .byteCount(style: .file))
        } label: {
            Text(item.displayName)
            if !item.kinds.isEmpty {
                Text(item.kinds.map { String(localized: $0.title) }.formatted(.list(type: .and)))
            }
            Text("Last opened \(item.lastOpened, format: .dateTime.day().month().year())")
            if !item.isPDFFound {
                // One line: a `Label` here puts its icon on a line of its own.
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .accessibilityHidden(true)
                    Text("PDF not found")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension StoredDataKind {
    var title: LocalizedStringResource {
        switch self {
        case .notes: "Notes"
        case .drawings: "Drawings"
        case .settings: "Settings"
        }
    }
}
