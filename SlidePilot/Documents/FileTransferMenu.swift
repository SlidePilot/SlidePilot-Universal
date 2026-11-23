#if os(iOS)
import SwiftUI

/// Import Notes…, Export Notes…, Export Drawings… and the `.slidepilot` file (NOTES-11) in one toolbar menu on iPad, where the
/// menu bar is hidden until it is pulled down (NOTES-06, DRAW-10). One menu keeps the
/// toolbar short and names each command next to its symbol.
struct FileTransferMenu: View {
    // From the environment: focused values do not reach a toolbar menu on iPad.
    @Environment(\.notesFile) private var notesFile
    @Environment(\.drawingsExport) private var drawingsExport
    @Environment(\.slidePilotFile) private var slidePilotFile

    var body: some View {
        Menu {
            Button("Import Notes…", systemImage: "square.and.arrow.down") { notesFile?.importNotes() }
                .disabled(notesFile == nil)
            Button("Export Notes…", systemImage: "square.and.arrow.up") { notesFile?.exportNotes() }
                .disabled(notesFile == nil)
            if let item = drawingsExport?.item {
                // A share sheet: Save to Files, AirDrop, Mail.
                ShareLink(item: item, preview: SharePreview(item.fileName)) {
                    Label("Export Drawings…", systemImage: DrawingsExportCommands.symbol)
                }
            }
            // Notes, drawings and settings in one file (NOTES-11).
            Section {
                Button("Import SlidePilot File…", systemImage: SlidePilotFileCommands.importSymbol) {
                    slidePilotFile?.importFile()
                }
                .disabled(slidePilotFile == nil)
                if let item = slidePilotFile?.shareItem {
                    ShareLink(item: item, preview: SharePreview(item.fileName)) {
                        Label("Export SlidePilot File…", systemImage: SlidePilotFileCommands.exportSymbol)
                    }
                }
            }
        } label: {
            Label("Import and Export", systemImage: "arrow.up.arrow.down.square")
        }
    }
}
#endif
