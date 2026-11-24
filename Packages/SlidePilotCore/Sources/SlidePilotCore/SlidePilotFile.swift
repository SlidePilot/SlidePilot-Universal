import Foundation

/// The stored data of one PDF as a file users can keep, move and share: a `.slidepilot`
/// file (NOTES-11, ADR 0019).
///
/// Holds what the companion entry holds, without what only makes sense on one device: the
/// PDF's bookmark and document identifier (they contain local paths), the entry ID, the
/// last-opened date, declined orphans (NOTES-12) and declined legacy notes (NOTES-08).
/// The PDF itself is never part of it.
public struct SlidePilotFile: Sendable, Equatable {
    /// The PDF's file name when the file was exported, to warn about a mismatch on import.
    public var pdfFileName: String
    public var pdfPageCount: Int
    public var exportedAt: Date
    public var settings: DocumentSettings
    public var notes: CompanionNotes?
    public var drawings: CompanionDrawings?

    public init(
        pdfFileName: String, pdfPageCount: Int, exportedAt: Date,
        settings: DocumentSettings = DocumentSettings(), notes: CompanionNotes? = nil, drawings: CompanionDrawings? = nil
    ) {
        self.pdfFileName = pdfFileName
        self.pdfPageCount = pdfPageCount
        self.exportedAt = exportedAt
        self.settings = settings.withoutDeviceState
        self.notes = notes?.isEmpty == false ? notes : nil
        self.drawings = drawings?.isEmpty == false ? drawings : nil
    }

    /// The data of a companion entry, without device state.
    public init(entry: CompanionEntry, exportedAt: Date) {
        self.init(
            pdfFileName: entry.pdf.fileName, pdfPageCount: entry.pdf.pageCount, exportedAt: exportedAt,
            settings: entry.settings, notes: entry.notes, drawings: entry.drawings
        )
    }

    /// What the file holds, in the order of `StoredDataKind.allCases`.
    public var kinds: [StoredDataKind] {
        StoredDataKind.allCases.filter { kind in
            switch kind {
            case .notes: notes != nil
            case .drawings: drawings != nil
            case .settings: !settings.isEmpty
            }
        }
    }

    /// How the file differs from the PDF it is imported into.
    public struct Mismatch: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let fileName = Mismatch(rawValue: 1 << 0)
        public static let pageCount = Mismatch(rawValue: 1 << 1)
    }

    public func mismatch(withPDFNamed fileName: String?, pageCount: Int) -> Mismatch {
        var mismatch: Mismatch = []
        if let fileName, fileName != pdfFileName {
            mismatch.insert(.fileName)
        }
        if pageCount != pdfPageCount {
            mismatch.insert(.pageCount)
        }
        return mismatch
    }

    /// The suggested file name: `<pdf>.slidepilot` (NOTES-11).
    public static func exportName(forPDFBaseName baseName: String?, untitled: String) -> String {
        let name = baseName.flatMap { $0.isEmpty ? nil : $0 } ?? untitled
        return "\(name).\(SlidePilotFileFormat.fileExtension)"
    }
}

extension CompanionEntry {
    /// Takes over the data of a `.slidepilot` file (NOTES-11): its notes replace the stored
    /// ones, its settings override the stored ones, and with `includingDrawings` its drawings
    /// replace the stored ones. The PDF reference stays.
    public mutating func importFile(_ file: SlidePilotFile, includingDrawings: Bool) {
        settings = settings.overridden(by: file.settings)
        notes = file.notes
        if includingDrawings {
            drawings = file.drawings
        }
    }
}

extension DocumentSettings {
    /// The settings without the state of one device: whether the legacy notes file next to
    /// the PDF was declined (NOTES-08) only applies to that file.
    var withoutDeviceState: DocumentSettings {
        var settings = self
        settings.declinedLegacyNotes = nil
        return settings
    }

    /// These settings with every setting `other` holds taken over (NOTES-11). Settings that
    /// `other` does not hold mean "not saved there", so the stored ones stay.
    public func overridden(by other: DocumentSettings) -> DocumentSettings {
        var result = self
        if let layout = other.layout { result.layout = layout }
        if let isNavigatorDisplayed = other.isNavigatorDisplayed { result.isNavigatorDisplayed = isNavigatorDisplayed }
        if let isPointerDisplayed = other.isPointerDisplayed { result.isPointerDisplayed = isPointerDisplayed }
        if let pointerAppearance = other.pointerAppearance { result.pointerAppearance = pointerAppearance }
        if let notesMode = other.notesMode { result.notesMode = notesMode }
        if let notesPosition = other.notesPosition { result.notesPosition = notesPosition }
        return result
    }
}

/// The versioned encoding of a `.slidepilot` file (NOTES-11, ADR 0019).
///
/// UTF-8 JSON: `{"slidePilotFileVersion": 1, "exportedAt": …, "pdf": {"fileName", "pageCount"},
/// "settings": …, "notes": …, "drawings": …}`. Settings, notes and drawings use the
/// companion file's encodings. Readers ignore unknown keys, so new optional fields keep the
/// version; it only goes up when a field changes its meaning, and `decode` then migrates
/// older versions. Files from a later version are refused, so no data is silently dropped.
public enum SlidePilotFileFormat {
    public static let currentVersion = 1
    public static let fileExtension = "slidepilot"

    public enum DecodingError: Error, Equatable, Sendable {
        /// The data is not a `.slidepilot` file, or it is damaged.
        case unreadable
        /// Written by a later app version that this version cannot read safely.
        case newerVersion
    }

    private struct PDF: Codable {
        var fileName: String
        var pageCount: Int
    }

    private struct Envelope: Codable {
        var slidePilotFileVersion: Int
        var exportedAt: Date
        var pdf: PDF
        var settings: DocumentSettings?
        var notes: CompanionNotes?
        var drawings: CompanionDrawings?
    }

    private struct VersionOnly: Decodable {
        var slidePilotFileVersion: Int
    }

    public static func encode(_ file: SlidePilotFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(
            slidePilotFileVersion: currentVersion,
            exportedAt: file.exportedAt,
            pdf: PDF(fileName: file.pdfFileName, pageCount: file.pdfPageCount),
            settings: file.settings.isEmpty ? nil : file.settings,
            notes: file.notes,
            drawings: file.drawings
        ))
    }

    public static func decode(_ data: Data) throws(DecodingError) -> SlidePilotFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let version = try? decoder.decode(VersionOnly.self, from: data).slidePilotFileVersion, version >= 1 else {
            throw .unreadable
        }
        guard version <= currentVersion else { throw .newerVersion }
        // Strict: damaged notes or drawings fail the import instead of replacing data with less.
        guard let envelope = try? decoder.decode(Envelope.self, from: data), envelope.pdf.pageCount >= 0 else {
            throw .unreadable
        }
        return SlidePilotFile(
            pdfFileName: envelope.pdf.fileName,
            pdfPageCount: envelope.pdf.pageCount,
            exportedAt: envelope.exportedAt,
            settings: envelope.settings ?? DocumentSettings(),
            notes: envelope.notes,
            drawings: envelope.drawings
        )
    }
}
