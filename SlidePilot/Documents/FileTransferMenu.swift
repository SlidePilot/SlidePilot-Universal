#if os(iOS)
import SwiftUI

/// Import Notes…, Export Notes… and Export Drawings… in one toolbar menu on iPad and iPhone:
/// the iPad hides its menu bar until it is pulled down, the iPhone has none (NOTES-06,
/// DRAW-10). One menu keeps the toolbar short and names each command next to its symbol.
struct FileTransferMenu: View {
    @FocusedValue(\.notesFile) private var notesFile
    @FocusedValue(\.drawingsExport) private var drawingsExport

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
        } label: {
            Label("Import and Export", systemImage: "arrow.up.arrow.down.square")
        }
    }
}
#endif
