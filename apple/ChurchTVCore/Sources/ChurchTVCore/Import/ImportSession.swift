import Foundation
import CoreGraphics

/// An opened PowerPoint, PDF or set of pictures: the list of entries for the preview, thumbnails, and the code that turns an entry
/// into upload-ready files. Pure Core code (no UI, no network) so it can be tested with fixture files.
public final class ImportSession: @unchecked Sendable {
    public let kind: ImportKind
    /// Display name without extension. Also the default name of the media folder and of a new deck or playlist.
    public let name: String
    public let entries: [ImportEntry]
    /// Videos and audio inside a .pptx (listed with tick boxes).
    public let mediaEntries: [ImportMediaEntry]
    /// Things worth telling the user before importing.
    public let notices: [String]
    public let slides: [Int: PPTXSlide]
    /// Slide width / height of a .pptx (16:9 unless the file says otherwise).
    public let aspect: Double
    /// Number of pages/slides/pictures (used to pad file numbers).
    let total: Int
    let pdf: PDFSource?
    let package: PPTXPackage?

    init(kind: ImportKind, name: String, entries: [ImportEntry], mediaEntries: [ImportMediaEntry] = [], notices: [String] = [],
         slides: [Int: PPTXSlide] = [:], aspect: Double = 16.0 / 9.0, total: Int, pdf: PDFSource? = nil, package: PPTXPackage? = nil) {
        self.kind = kind; self.name = name; self.entries = entries; self.mediaEntries = mediaEntries; self.notices = notices
        self.slides = slides; self.aspect = aspect; self.total = total; self.pdf = pdf; self.package = package
    }

    static let pptxExtensions: Set<String> = ["pptx", "pptm", "ppsx", "potx"]
    /// png, jpg, jpeg, webp, gif as the web accepts, plus formats an iPhone or Mac produces (converted to JPEG on import).
    static let pictureExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "tif", "tiff", "bmp"]

    // MARK: Opening

    /// Opens the chosen file(s). Throws `ImportError`, `PDFImportError`, `PPTXError` or `ZipError`; all have text for people.
    /// Files must already be readable by the app (the UI copies picked files into a temporary folder first).
    public static func open(urls: [URL]) throws -> ImportSession {
        guard !urls.isEmpty else { throw ImportError.noFiles }
        let exts = urls.map { $0.pathExtension.lowercased() }
        if exts.allSatisfy({ pictureExtensions.contains($0) }) { return try openPictures(urls) }
        if let bad = exts.first(where: { !pictureExtensions.contains($0) && $0 != "pdf" && !pptxExtensions.contains($0) }) { throw ImportError.unsupported(bad) }
        guard urls.count == 1 else { throw ImportError.mixed }
        let url = urls[0]
        return exts[0] == "pdf" ? try openPDF(url) : try openPPTX(url)
    }

    static func openPDF(_ url: URL) throws -> ImportSession {
        let pdf = try PDFSource(url: url)
        if pdf.pageCount > ImportLimits.hardMaxPages { throw ImportError.tooMany(pdf.pageCount) }
        var entries: [ImportEntry] = []
        for n in 1...pdf.pageCount {
            let size = pdf.renderSize(n, longEdge: ImportLimits.renderLongEdge)
            entries.append(ImportEntry(number: n, title: "Page \(n)", detail: size.map { "\($0.width) x \($0.height)" } ?? "Cannot be drawn", payload: .pdfPage(n),
                                       style: .picture, included: size != nil && n <= ImportLimits.maxPages, enabled: size != nil,
                                       warning: size == nil ? "This page has no size and cannot be drawn." : nil))
        }
        var notices: [String] = []
        if pdf.pageCount > ImportLimits.maxPages { notices.append("This PDF has \(pdf.pageCount) pages. Only the first \(ImportLimits.maxPages) can be imported at a time: they are ticked, the rest are not. Import the rest in a second pass.") }
        return ImportSession(kind: .pdf, name: ImportNaming.baseName(url.lastPathComponent), entries: entries, notices: notices, total: pdf.pageCount, pdf: pdf)
    }

    static func openPictures(_ picked: [URL]) throws -> ImportSession {
        let urls = picked.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var entries: [ImportEntry] = []
        for (i, url) in urls.enumerated() {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            var warning: String?
            var detail = Formatting.bytes(size)
            if size > ImportLimits.maxUploadBytes {
                warning = "Larger than \(ImportLimits.uploadLimitText); it cannot be uploaded."
            } else if let data = try? Data(contentsOf: url, options: .mappedIfSafe), let px = ImageTools.pixelSize(of: data) {
                detail = "\(Int(px.width)) x \(Int(px.height)), \(Formatting.bytes(size))"
            } else {
                warning = "This file could not be read as a picture."
            }
            entries.append(ImportEntry(number: i + 1, title: url.deletingPathExtension().lastPathComponent, detail: detail, payload: .imageFile(url), style: .picture,
                                       included: warning == nil && i < ImportLimits.maxPages, enabled: warning == nil, warning: warning))
        }
        var notices: [String] = []
        if urls.count > ImportLimits.maxPages { notices.append("You chose \(urls.count) pictures. Only the first \(ImportLimits.maxPages) can be imported at a time: they are ticked, the rest are not.") }
        let name = ImportNaming.folderName(forImageFiles: urls.map(\.lastPathComponent))
        return ImportSession(kind: .images, name: name, entries: entries, notices: notices, total: urls.count)
    }

    static func openPPTX(_ url: URL) throws -> ImportSession {
        let pkg = try PPTXPackage(url: url)
        if pkg.slides.count > ImportLimits.hardMaxPages { throw ImportError.tooMany(pkg.slides.count) }
        func firstLine(_ s: String) -> String { String((s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "").prefix(90)) }
        var entries: [ImportEntry] = []
        var map: [Int: PPTXSlide] = [:]
        var mediaEntries: [ImportMediaEntry] = []
        var charts = 0
        for s in pkg.slides {
            map[s.number] = s
            let pic = s.mainPicture
            let hasMedia = s.media.contains { $0.supported }
            let enabled = s.kind != .empty || hasMedia
            var bits: [String] = []
            if s.hidden { bits.append("Hidden slide") }
            if !s.notes.isEmpty { bits.append("speaker notes") }
            if s.kind == .picture { bits.append(pic != nil ? "picture slide" : "picture format not supported") }
            if s.kind == .empty && !enabled { bits.append("nothing to import") }
            if s.hasChartOrDiagram { charts += 1; bits.append("chart or diagram not imported") }
            let label = !s.title.isEmpty ? firstLine(s.title) : (!s.body.isEmpty ? firstLine(s.body) : (s.kind == .picture ? "Picture" : "Empty slide"))
            let style: ImportEntry.Style = s.kind == .text ? .text : s.kind == .picture ? .picture : .empty
            let importable = !(s.kind == .picture && pic == nil)
            entries.append(ImportEntry(number: s.number, title: "\(s.number). \(label)", detail: bits.joined(separator: " · "), payload: .pptxSlide(s.number), style: style,
                                       included: enabled && !s.hidden && importable && s.number <= ImportLimits.maxPages, enabled: enabled,
                                       warning: s.kind == .picture && pic == nil ? "The picture is in a format that cannot be imported. Export the slides as PNG pictures from PowerPoint instead." : nil))
            for m in s.media {
                var reason: String?
                if let link = m.external { reason = "Online video (\(link)). Add it as a Live stream or YouTube item instead." }
                else if !m.supported { reason = "Format not supported (.\(m.ext))." }
                else if (m.size ?? 0) > ImportLimits.maxUploadBytes { reason = "Larger than \(ImportLimits.uploadLimitText)." }
                let name = m.external != nil ? "Online video" : m.filename
                let detail = m.kind == .audio && reason == nil ? "audio: added to the media library only" : (m.size.map { Formatting.bytes($0) } ?? "")
                mediaEntries.append(ImportMediaEntry(id: "\(s.number)|\(m.id)", slideNumber: s.number, media: m, included: reason == nil, disabledReason: reason,
                                                     detail: "\(name)" + (detail.isEmpty ? "" : " · \(detail)")))
            }
        }
        var notices: [String] = []
        if pkg.slides.count > ImportLimits.maxPages { notices.append("This PowerPoint has \(pkg.slides.count) slides. Only the first \(ImportLimits.maxPages) can be imported at a time: they are ticked, the rest are not. Import the rest in a second pass.") }
        if charts > 0 { notices.append("\(charts) slide\(charts == 1 ? " has" : "s have") a chart or diagram that is not imported. Export to PDF for an exact look.") }
        return ImportSession(kind: .pptx, name: ImportNaming.baseName(url.lastPathComponent), entries: entries, mediaEntries: mediaEntries, notices: notices,
                             slides: map, aspect: pkg.aspect, total: pkg.slides.count, package: pkg)
    }

    // MARK: Preview material

    /// A small JPEG for the preview row (nil for text slides, which the UI draws itself).
    public func thumbnail(for entry: ImportEntry) -> Data? {
        switch entry.payload {
        case .pdfPage(let n): return pdf?.render(page: n, longEdge: 360).flatMap { ImageTools.jpeg($0, quality: 0.7) }
        case .imageFile(let url): return ImageTools.thumbnail(ofFile: url)
        case .pptxSlide(let n):
            guard let s = slides[n], s.kind == .picture, let pic = s.mainPicture, let data = try? package?.fileData(path: pic.path) else { return nil }
            return ImageTools.thumbnail(of: data)
        }
    }

    /// Title and body of a PowerPoint text slide (for the preview card), or nil.
    public func text(for entry: ImportEntry) -> ImportedText? {
        guard case .pptxSlide(let n) = entry.payload, let s = slides[n], s.kind == .text else { return nil }
        return ImportedText(title: s.title, body: s.body)
    }

    // MARK: Planning

    /// The pieces of work for one ticked entry, in the order their slides/items appear. Throws a message safe to show.
    public func plan(_ entry: ImportEntry, options: ImportPlanOptions) throws -> [ImportPart] {
        let deck = options.mode == .deck
        switch entry.payload {
        case .pdfPage(let n):
            return [ImportPart(source: .pdfPage(n), text: nil, fileName: ImportNaming.pageFileName(base: name, number: n, total: total, ext: "jpg"), role: .page, notes: "", isVideo: false)]
        case .imageFile(let url):
            return [ImportPart(source: .imageFile(url), text: nil, fileName: url.lastPathComponent, role: .page, notes: "", isVideo: false)]
        case .pptxSlide(let n):
            guard let s = slides[n] else { throw ChurchError("Slide \(n) was not found.") }
            let nn = ImportNaming.pageFileName(base: name, number: s.number, total: total, ext: "")
            var parts: [ImportPart] = []
            switch s.kind {
            case .text:
                if deck {
                    parts.append(ImportPart(source: nil, text: ImportedText(title: s.title, body: s.body), fileName: "", role: .page, notes: s.notes, isVideo: false))
                } else {
                    parts.append(ImportPart(source: .textPicture(title: s.title, body: s.body), text: nil, fileName: "\(nn).jpg", role: .page, notes: "", isVideo: false))
                }
                if options.withPictures && deck {
                    for (k, p) in s.pictures.filter(\.supported).enumerated() {
                        parts.append(ImportPart(source: .pptxFile(path: p.path), text: nil, fileName: "\(nn) picture \(k + 1).\(p.ext)", role: .page, notes: "", isVideo: false))
                    }
                }
            case .picture:
                guard let p = s.mainPicture else {
                    let ext = s.pictures.first?.ext ?? s.bgPicture?.ext ?? "unknown"
                    throw ChurchError("The picture is in a format that can't be imported (\(ext)). Export the slides as PNG pictures from PowerPoint instead.")
                }
                parts.append(ImportPart(source: .pptxFile(path: p.path), text: nil, fileName: "\(nn).\(p.ext)", role: .page, notes: deck ? s.notes : "", isVideo: false))
            case .empty: break
            }
            for m in s.media where options.mediaOn.contains(m.path) && !m.path.isEmpty {
                parts.append(ImportPart(source: .pptxFile(path: m.path), text: nil, fileName: "\(nn) \(m.filename)", role: m.kind == .video ? .page : .libraryOnly, notes: "", isVideo: m.kind == .video))
            }
            return parts
        }
    }

    // MARK: Preparing uploads

    /// Creates the file for a part (render, extract or convert) inside `directory`. `backgroundHex` is the church colour for text pictures.
    public func prepare(_ part: ImportPart, directory: URL, backgroundHex: String? = nil) throws -> PreparedFile {
        guard let source = part.source else { throw ChurchError("Nothing to upload for this slide.") }
        var fileName = part.fileName
        let data: Data
        var contentType: String
        var kind: MediaKind = .image
        switch source {
        case .pdfPage(let n):
            guard let pdf, let cg = pdf.render(page: n, longEdge: ImportLimits.renderLongEdge), let d = ImageTools.jpeg(cg, quality: ImportLimits.jpegQuality) else { throw ChurchError("Page \(n) could not be drawn.") }
            data = d; contentType = "image/jpeg"
        case .textPicture(let title, let body):
            guard let cg = TextSlideRenderer.render(title: title, body: body, backgroundHex: backgroundHex ?? ImportLimits.kidsBackgroundDefault, aspect: aspect),
                  let d = ImageTools.jpeg(cg, quality: ImportLimits.jpegQuality) else { throw ChurchError("The slide could not be drawn as a picture.") }
            data = d; contentType = "image/jpeg"
        case .imageFile(let url):
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            if size > ImportLimits.maxUploadBytes { throw ImportError.tooBig(url.lastPathComponent, size) }
            guard let raw = try? Data(contentsOf: url, options: .mappedIfSafe), let p = ImageTools.prepare(raw) else { throw ChurchError("\(url.lastPathComponent) is not a picture the app can read.") }
            data = p.data; contentType = p.contentType
            fileName = (fileName as NSString).deletingPathExtension + "." + p.fileExtension
        case .pptxFile(let path):
            guard let package else { throw ChurchError("No presentation is open.") }
            let raw: Data?
            do { raw = try package.fileData(path: path) } catch { throw ChurchError("\((path as NSString).lastPathComponent) is larger than \(ImportLimits.uploadLimitText) or damaged.") }
            guard let raw else { throw ChurchError("The file is missing from the PowerPoint.") }
            let ext = (path as NSString).pathExtension.lowercased()
            if let mime = Self.mediaTypes[ext] {
                data = raw; contentType = mime; kind = mime.hasPrefix("video/") ? .video : .audio
            } else {
                guard let p = ImageTools.prepare(raw) else { throw ChurchError("The picture is in a format that can't be imported (\(ext)). Export the slides as PNG pictures from PowerPoint instead.") }
                data = p.data; contentType = p.contentType
                fileName = (fileName as NSString).deletingPathExtension + "." + p.fileExtension
            }
        }
        if Int64(data.count) > ImportLimits.maxUploadBytes { throw ChurchError("The file is over \(ImportLimits.uploadLimitText).") }
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(ImportNaming.safeFileName(fileName))")
        do { try data.write(to: url) } catch { throw ChurchError("Could not save \(fileName) for upload.") }
        return PreparedFile(url: url, filename: fileName, title: (fileName as NSString).deletingPathExtension, contentType: contentType, kind: kind, size: Int64(data.count))
    }

    static let mediaTypes: [String: String] = [
        "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "webm": "video/webm",
        "mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac", "wav": "audio/wav", "ogg": "audio/ogg",
    ]
}
