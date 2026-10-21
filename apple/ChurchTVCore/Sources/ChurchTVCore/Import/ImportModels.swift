import Foundation

// Limits, names and data types of the PDF / PowerPoint / picture importer. Mirrors dashboard/src/importer/ and PPTX-IMPORT-CONTRACT.md.

/// Limits for importing PowerPoint, PDF and pictures. Shown to people in the import screen.
public enum ImportLimits {
    /// Pages, slides or pictures per import.
    public static let maxPages = 150
    /// Largest .pptx or PDF.
    public static let maxDocumentBytes: Int64 = 150 * 1024 * 1024
    /// Largest single uploaded file (rendered page, picture, video, audio): the free Supabase plan refuses more.
    public static let maxUploadBytes: Int64 = 50 * 1024 * 1024
    /// A file with more pages than this is refused outright.
    public static let hardMaxPages = 2_000
    /// PDF pages are rendered with this longest side (16:9 pages become 1920x1080).
    public static let renderLongEdge = 1920
    public static let jpegQuality = 0.9
    public static let uploadLimitText = "50 MB"
    public static let documentLimitText = "150 MB"
    /// Parallel uploads.
    public static let uploadsInFlight = 3

    public static var summary: String {
        "Up to \(maxPages) pages per import, files up to \(Formatting.bytes(maxDocumentBytes)), each uploaded picture or video up to \(Formatting.bytes(maxUploadBytes))."
    }
    /// The tip shown in the import screen.
    public static let exportTip = "In PowerPoint choose File > Export > PDF for an exact look."
    public static let kidsBackgroundDefault = "#1f3a5f"
}

public enum ImportKind: String, Hashable, Sendable {
    case pdf, pptx, images
    /// What a person calls one unit of this kind.
    public var unit: String { self == .pdf ? "page" : self == .pptx ? "slide" : "picture" }
}

/// Where the pages go: a Slides deck, or a Kids playlist (which has no text slide, so text is drawn as a picture).
public enum ImportMode: Hashable, Sendable { case deck, kidsPlaylist }

/// One row of the import preview: a page, a slide or a picture the user can tick, untick and reorder.
public struct ImportEntry: Identifiable, Hashable, Sendable {
    public enum Payload: Hashable, Sendable {
        /// 1-based PDF page.
        case pdfPage(Int)
        /// 1-based slide number in the .pptx.
        case pptxSlide(Int)
        /// A picture file (already copied somewhere the app can read).
        case imageFile(URL)
    }
    /// How the entry becomes content.
    public enum Style: String, Hashable, Sendable {
        case picture, text, empty
    }
    public var id: UUID
    /// Position in the source file (1-based).
    public var number: Int
    public var title: String
    public var detail: String
    public var payload: Payload
    public var style: Style
    public var included: Bool
    /// False for rows that cannot be ticked (an empty slide with nothing to import).
    public var enabled: Bool
    public var warning: String?

    public init(id: UUID = UUID(), number: Int, title: String, detail: String = "", payload: Payload, style: Style, included: Bool = true, enabled: Bool = true, warning: String? = nil) {
        self.id = id; self.number = number; self.title = title; self.detail = detail; self.payload = payload; self.style = style
        self.included = included; self.enabled = enabled; self.warning = warning
    }
}

/// A video or audio clip inside a PowerPoint slide, listed with a tick box.
public struct ImportMediaEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var slideNumber: Int
    public var media: PPTXMedia
    public var included: Bool
    /// Why it cannot be imported (nil = importable).
    public var disabledReason: String?
    public var detail: String
}

/// Where imported pages go.
public enum ImportPlacement: Hashable, Sendable {
    case append
    /// After slide/item number `n` (0 = at the start).
    case after(Int)
    /// A new deck or playlist with this name.
    case newItem(name: String)
}

public struct ImportOptions: Hashable, Sendable {
    /// Seconds each imported page shows; nil = wait for Next.
    public var seconds: Int?
    public init(seconds: Int? = nil) { self.seconds = seconds }
}

/// Everything the importer needs to know to turn one entry into uploads and slides.
public struct ImportPlanOptions: Hashable, Sendable {
    public var mode: ImportMode
    /// Decks only: also add each supported picture of a text slide as a picture slide right after it.
    public var withPictures: Bool
    /// Paths of the media files the user ticked.
    public var mediaOn: Set<String>
    public init(mode: ImportMode, withPictures: Bool = false, mediaOn: Set<String> = []) { self.mode = mode; self.withPictures = withPictures; self.mediaOn = mediaOn }
}

/// One piece of work for an entry. An entry usually has one part; PowerPoint slides can have several (text, pictures, videos).
public struct ImportPart: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case pdfPage(Int)
        case imageFile(URL)
        case pptxFile(path: String)
        /// A text slide drawn as a picture (Kids playlists).
        case textPicture(title: String, body: String)
    }
    public enum Role: Hashable, Sendable {
        /// Becomes a slide or item.
        case page
        /// Uploaded to the media library only (audio).
        case libraryOnly
    }
    /// nil source = a deck text slide: nothing to upload.
    public var source: Source?
    public var text: ImportedText?
    /// Name of the uploaded file, with extension, for example "Easter Sunday 03.jpg".
    public var fileName: String
    public var role: Role
    public var notes: String
    public var isVideo: Bool
}

public struct ImportedText: Hashable, Sendable {
    public var title: String
    public var body: String
    public init(title: String, body: String) { self.title = title; self.body = body }
}

/// A picture or video file on disk ready to hand to the media upload.
public struct PreparedFile: Sendable {
    public var url: URL
    public var filename: String
    /// File name without the extension: becomes the library title.
    public var title: String
    public var contentType: String
    public var kind: MediaKind
    public var size: Int64
}

/// The result for one part after upload: the library row, or the text of a deck text slide.
public struct ImportedPage: Sendable {
    public var entryNumber: Int
    public var media: MediaItem?
    public var text: ImportedText?
    /// Speaker notes (decks only).
    public var notes: String
    public init(entryNumber: Int, media: MediaItem? = nil, text: ImportedText? = nil, notes: String = "") {
        self.entryNumber = entryNumber; self.media = media; self.text = text; self.notes = notes
    }
}

/// A page that could not be imported and why.
public struct ImportFailure: Hashable, Sendable, Identifiable {
    public var id: UUID { entryId }
    public var entryId: UUID
    public var label: String
    public var reason: String
    public init(entryId: UUID, label: String, reason: String) { self.entryId = entryId; self.label = label; self.reason = reason }
}

public enum ImportError: Error, LocalizedError, Equatable {
    case unsupported(String)
    case mixed
    case noFiles
    case tooMany(Int)
    case tooBig(String, Int64)
    public var errorDescription: String? {
        switch self {
        case .unsupported(let ext):
            if ext == "ppt" || ext == "pps" || ext == "pot" { return "Old .ppt files are not supported. In PowerPoint use File > Save As > PowerPoint Presentation (.pptx), or export to PDF." }
            if ext == "key" { return "Keynote files are not supported. In Keynote use File > Export To > PDF (or Images)." }
            return "Choose a PDF, a PowerPoint (.pptx) or picture files (PNG, JPG)."
        case .mixed: return "Choose one PowerPoint file, one PDF, or several pictures. They cannot be mixed in one import."
        case .noFiles: return "No file was chosen."
        case .tooMany(let n): return "This file has \(n) pages, which is more than can be imported."
        case .tooBig(let name, let n): return "\(name) is \(Formatting.bytes(n)). The limit for one picture is \(ImportLimits.uploadLimitText)."
        }
    }
}

/// File and folder names (same rules as importLogic.ts).
public enum ImportNaming {
    public static func baseName(_ file: String) -> String {
        var n = file
        if let dot = n.lastIndex(of: "."), n.index(after: dot) < n.endIndex { n = String(n[..<dot]) }   // like replace(/\.[^.]+$/, "")
        n = n.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Imported" : n
    }

    /// "Easter Sunday" + page 3 of 12 -> "Easter Sunday 03.jpg". The number keeps the page number of the source file.
    public static func pageFileName(base: String, number: Int, total: Int, ext: String) -> String {
        let width = max(2, String(total).count)
        let n = String(format: "%0\(width)d", number)
        return ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
    }

    /// Folder name for picture files: their shared start ("Slide" from Slide1.png, Slide2.png), else "Imported pictures YYYY-MM-DD".
    public static func folderName(forImageFiles names: [String], today: Date = Date()) -> String {
        let bases = names.map(baseName)
        if bases.count == 1 { return bases[0] }
        var prefix = bases.first ?? ""
        for b in bases { while !prefix.isEmpty && !b.lowercased().hasPrefix(prefix.lowercased()) { prefix.removeLast() } }
        let strip = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-_.0123456789"))
        prefix = prefix.trimmingCharacters(in: strip)
        if prefix.count >= 3 { return prefix }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        return "Imported pictures \(f.string(from: today))"
    }

    /// "Easter" -> "Easter", or "Easter (2)" when taken (case-insensitive).
    public static func uniqueFolderName(wanted: String, taken: [String]) -> String {
        let used = Set(taken.map { $0.lowercased() })
        var name = wanted
        var i = 2
        while used.contains(name.lowercased()) { name = "\(wanted) (\(i))"; i += 1 }
        return name
    }

    /// File-name safe stem for temporary files.
    static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0}")
        let cleaned = s.unicodeScalars.map { bad.contains($0) ? "-" : Character($0) }
        return String(cleaned)
    }
}
