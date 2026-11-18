import Foundation

/// How the companion entry finds its PDF again (ADR 0012).
public struct PDFReference: Codable, Sendable, Equatable {
    /// Bookmark of the PDF; it follows renames and moves on the same volume.
    public var bookmark: Data
    /// The PDF's file name when it was last opened, for the orphaned data hint (NOTES-12)
    /// and the stored data overview (SET-07).
    public var fileName: String
    public var pageCount: Int
    /// The system's persistent document identifier, where one exists (iPadOS).
    public var documentIdentifier: Int?

    public init(bookmark: Data, fileName: String, pageCount: Int, documentIdentifier: Int? = nil) {
        self.bookmark = bookmark
        self.fileName = fileName
        self.pageCount = pageCount
        self.documentIdentifier = documentIdentifier
    }
}

/// Settings stored per document (SET-02). Every field is optional: `nil` means "not saved
/// for this document", so the app default or the global last-used value applies.
///
/// New fields are added as optionals and decoded leniently, so older files stay readable.
/// The curtain state is never stored (CUR-03).
public struct DocumentSettings: Sendable, Equatable {
    /// The presenter layout of this document (LAY-05).
    public var layout: PresenterLayout?
    /// Whether the slide navigator sidebar is shown (LAY-06).
    public var isNavigatorDisplayed: Bool?
    /// The user did not allow access to the folder of a legacy notes file found next to the
    /// PDF (NOTES-08), so the app does not ask again for this PDF.
    public var declinedLegacyNotes: Bool?

    public init(layout: PresenterLayout? = nil, isNavigatorDisplayed: Bool? = nil, declinedLegacyNotes: Bool? = nil) {
        self.layout = layout
        self.isNavigatorDisplayed = isNavigatorDisplayed
        self.declinedLegacyNotes = declinedLegacyNotes
    }

    public var isEmpty: Bool { self == DocumentSettings() }
}

extension DocumentSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case layout, isNavigatorDisplayed, declinedLegacyNotes
    }

    /// A damaged or unknown field falls back to "not saved" instead of failing the entry.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try? container.decodeIfPresent(PresenterLayout.self, forKey: .layout)
        isNavigatorDisplayed = try? container.decodeIfPresent(Bool.self, forKey: .isNavigatorDisplayed)
        declinedLegacyNotes = try? container.decodeIfPresent(Bool.self, forKey: .declinedLegacyNotes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(layout, forKey: .layout)
        try container.encodeIfPresent(isNavigatorDisplayed, forKey: .isNavigatorDisplayed)
        try container.encodeIfPresent(declinedLegacyNotes, forKey: .declinedLegacyNotes)
    }
}

/// The text notes of a document (NOTES-10): one encoded document per page, in page order.
///
/// Core only stores the bytes and their format; SlidePilotRendering converts them
/// (`CompanionNotesRTF`). The page count is independent of the PDF's: after a reload with
/// fewer pages, notes of the missing pages are kept; pages beyond the stored ones have none.
public struct CompanionNotes: Codable, Sendable, Equatable {
    /// How the pages are encoded. A struct, not an enum, so a format added later still
    /// decodes and its notes are kept instead of being dropped.
    public struct Format: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// One RTF document per page; fonts are stored by name, so Mac and iPad read the same notes.
        public static let rtf = Format(rawValue: "rtf")
    }

    public var format: Format
    /// Empty data is a page without notes.
    public var pages: [Data]

    public init(format: Format, pages: [Data]) {
        self.format = format
        self.pages = pages
    }

    public var isEmpty: Bool { pages.allSatisfy(\.isEmpty) }
}

/// Everything SlidePilot stores for one PDF: one entry per companion file in the app
/// container (NOTES-10, ADR 0012).
public struct CompanionEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var pdf: PDFReference
    /// Updated on every open; the expiry counts from here (SET-03, not from the last save
    /// like the old app, DEF-10).
    public var lastOpened: Date
    public var settings: DocumentSettings
    /// Text notes (NOTES-10); `nil` until notes were written.
    public var notes: CompanionNotes?
    /// Entries for other PDFs whose orphaned data the user declined to take over for this
    /// PDF (NOTES-12), so the app does not ask again for that pair.
    public var declinedOrphans: Set<UUID>

    public init(
        id: UUID = UUID(),
        pdf: PDFReference,
        lastOpened: Date,
        settings: DocumentSettings = DocumentSettings(),
        notes: CompanionNotes? = nil,
        declinedOrphans: Set<UUID> = []
    ) {
        self.id = id
        self.pdf = pdf
        self.lastOpened = lastOpened
        self.settings = settings
        self.notes = notes
        self.declinedOrphans = declinedOrphans
    }

    private enum CodingKeys: String, CodingKey {
        case id, pdf, lastOpened, settings, notes, declinedOrphans
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Without these the entry cannot be matched to its PDF, so they are required.
        id = try container.decode(UUID.self, forKey: .id)
        pdf = try container.decode(PDFReference.self, forKey: .pdf)
        lastOpened = (try? container.decode(Date.self, forKey: .lastOpened)) ?? .distantPast
        settings = (try? container.decode(DocumentSettings.self, forKey: .settings)) ?? DocumentSettings()
        // Strict: damaged notes make the whole file unreadable, so a save never replaces
        // them with nothing.
        notes = try container.decodeIfPresent(CompanionNotes.self, forKey: .notes)
        declinedOrphans = (try? container.decode(Set<UUID>.self, forKey: .declinedOrphans)) ?? []
    }

    /// Whether the entry holds user content (notes, drawings) that never expires (ADR 0012).
    /// Drawings (DRAW-07) add their check here.
    public var holdsUserContent: Bool { !(notes?.isEmpty ?? true) }

    /// Entries that hold only settings expire 12 months after the last open (SET-03).
    public static let settingsLifetime = DateComponents(month: 12)

    public func isExpired(at now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        guard !holdsUserContent,
              let expiry = calendar.date(byAdding: Self.settingsLifetime, to: lastOpened)
        else { return false }
        return now >= expiry
    }
}

/// The versioned file format of a companion entry (NOTES-10).
///
/// The file is JSON: `{"formatVersion": 1, "entry": {…}}`. Readers ignore unknown keys, so
/// adding optional fields keeps the version. The version only goes up when a field changes
/// its meaning; `decode` then migrates older versions.
public enum CompanionFileFormat {
    public static let currentVersion = 1
    /// File extension of entries in the container.
    public static let fileExtension = "json"

    public enum DecodingError: Error, Equatable, Sendable {
        /// The data is not a companion file.
        case unreadable
    }

    /// A decoded file. `isFromNewerVersion` entries were written by a later app version;
    /// they are used but never overwritten, so fields this version does not know survive.
    public struct Decoded: Sendable, Equatable {
        public var entry: CompanionEntry
        public var formatVersion: Int
        public var isFromNewerVersion: Bool { formatVersion > CompanionFileFormat.currentVersion }
    }

    private struct Envelope: Codable {
        var formatVersion: Int
        var entry: CompanionEntry
    }

    private struct VersionOnly: Decodable {
        var formatVersion: Int
    }

    public static func encode(_ entry: CompanionEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(formatVersion: currentVersion, entry: entry))
    }

    public static func decode(_ data: Data) throws(DecodingError) -> Decoded {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let version = try? decoder.decode(VersionOnly.self, from: data).formatVersion,
              version >= 1,
              let envelope = try? decoder.decode(Envelope.self, from: data)
        else { throw .unreadable }
        return Decoded(entry: envelope.entry, formatVersion: version)
    }
}
