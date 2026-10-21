import Foundation

// PowerPoint (.pptx) reader. Mirrors dashboard/src/importer/pptx.ts and PPTX-IMPORT-CONTRACT.md (section 4) rule for rule:
// slide order from presentation.xml, text in tree order with the same title/body rules, notes, pictures, media relationships.
// Pure: no UI, no network.

/// A picture found on a slide (a file inside the package, `ppt/media/...`).
public struct PPTXPicture: Hashable, Sendable {
    public var path: String
    public var ext: String
    /// png, jpg, jpeg, gif, webp can be imported. Others (emf, wmf, tiff, svg...) cannot.
    public var supported: Bool
    /// Drawn size in EMU (width x height); 0 when unknown.
    public var area: Int
}

public struct PPTXMedia: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable { case video, audio }
    /// Path inside the package; empty for an online video link.
    public var path: String
    public var kind: Kind
    public var ext: String
    public var size: Int64?
    /// mp4, m4v, mov, webm (video) / mp3, m4a, aac, wav, ogg (audio).
    public var supported: Bool
    /// A link to an online video (YouTube etc.): listed only.
    public var external: String?
    public var id: String { path.isEmpty ? "link:\(external ?? "")" : path }
    public var filename: String { (path as NSString).lastPathComponent }
}

/// What was read from one slide of a .pptx.
public struct PPTXSlide: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case text, picture, empty }
    /// 1-based position in the presentation's slide order.
    public var number: Int
    public var path: String
    /// Marked "Hide slide" in PowerPoint.
    public var hidden: Bool
    public var title: String
    public var body: String
    /// Speaker notes ("" when none).
    public var notes: String
    public var pictures: [PPTXPicture]
    /// A picture used as the slide background.
    public var bgPicture: PPTXPicture?
    public var media: [PPTXMedia]
    public var kind: Kind
    /// Charts and diagrams are not imported (only used for a warning).
    public var hasChartOrDiagram: Bool
    public var id: Int { number }

    /// The picture a picture-only slide becomes: the largest drawn picture that can be imported, else the background.
    public var mainPicture: PPTXPicture? {
        let ok = pictures.filter(\.supported)
        if !ok.isEmpty { return ok.reduce(ok[0]) { $1.area > $0.area ? $1 : $0 } }
        if let bg = bgPicture, bg.supported { return bg }
        return nil
    }
}

public enum PPTXError: Error, LocalizedError, Equatable {
    case notPowerPoint
    case noSlides
    case tooLarge(Int64)
    public var errorDescription: String? {
        switch self {
        case .notPowerPoint: return "This doesn't look like a PowerPoint (.pptx) file. Old .ppt files must be saved as .pptx first (File > Save As)."
        case .noSlides: return "This PowerPoint has no slides."
        case .tooLarge(let n): return "This file is \(Formatting.bytes(n)). The limit is \(ImportLimits.documentLimitText). Export fewer slides, or a smaller file."
        }
    }
}

public final class PPTXPackage {
    public let zip: ZipArchive
    public private(set) var slides: [PPTXSlide] = []
    /// Slide width / height (16/9 = 1.777...).
    public private(set) var aspect: Double = 16.0 / 9.0

    static let pictureExt: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]
    static let videoExt: Set<String> = ["mp4", "m4v", "mov", "webm"]
    static let audioExt: Set<String> = ["mp3", "m4a", "aac", "wav", "ogg"]
    private static let xmlLimit = 8 * 1024 * 1024

    public convenience init(url: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if size > ImportLimits.maxDocumentBytes { throw PPTXError.tooLarge(size) }
        do { try self.init(zip: ZipArchive(url: url)) } catch ZipError.notAZip { throw PPTXError.notPowerPoint }
    }

    public convenience init(data: Data) throws {
        do { try self.init(zip: ZipArchive(data: data)) } catch ZipError.notAZip { throw PPTXError.notPowerPoint }
    }

    init(zip: ZipArchive) throws {
        self.zip = zip
        guard zip.entry(named: "ppt/presentation.xml") != nil else { throw PPTXError.notPowerPoint }
        try load()
        if slides.isEmpty { throw PPTXError.noSlides }
    }

    public func fileData(path: String, maxBytes: Int = Int(ImportLimits.maxUploadBytes)) throws -> Data? { try zip.data(named: path, maxBytes: maxBytes) }

    // MARK: Relationships

    struct Rel { var type: String; var target: String; var external: Bool }

    private func xml(_ name: String) throws -> XNode? {
        guard let d = try zip.data(named: name, maxBytes: Self.xmlLimit) else { return nil }
        return XMLTreeParser.parse(d)
    }

    /// Relationship id -> where it points (Target resolved against the folder of the part the rels belong to).
    static func parseRels(_ root: XNode?, baseDir: String) -> [String: Rel] {
        var out: [String: Rel] = [:]
        for r in root?.all("Relationship") ?? [] {
            guard let id = r.attr("Id") else { continue }
            let target = r.attr("Target") ?? ""
            let external = r.attr("TargetMode") == "External"
            out[id] = Rel(type: r.attr("Type") ?? "", target: external ? target : resolve(baseDir, target), external: external)
        }
        return out
    }

    /// "ppt/slides" + "../media/a.png" -> "ppt/media/a.png". A target starting with "/" is from the zip root.
    static func resolve(_ baseDir: String, _ target: String) -> String {
        let t = target.removingPercentEncoding ?? target
        var parts = t.hasPrefix("/") ? [] : baseDir.split(separator: "/").map(String.init)
        for seg in t.split(separator: "/", omittingEmptySubsequences: false) {
            if seg == ".." { _ = parts.popLast() } else if !seg.isEmpty && seg != "." { parts.append(String(seg)) }
        }
        return parts.joined(separator: "/")
    }

    private func rels(forPart path: String) throws -> [String: Rel] {
        let dir = (path as NSString).deletingLastPathComponent
        let file = (path as NSString).lastPathComponent
        return Self.parseRels(try xml("\(dir)/_rels/\(file).rels"), baseDir: dir)
    }

    private static func ext(of path: String) -> String { (path as NSString).pathExtension.lowercased() }

    // MARK: Load

    private func load() throws {
        guard let pres = try xml("ppt/presentation.xml") else { throw PPTXError.notPowerPoint }
        let presRels = Self.parseRels(try xml("ppt/_rels/presentation.xml.rels"), baseDir: "ppt")
        // Slide order = the order of sldId entries (file names mean nothing).
        var paths = pres.all("sldId").compactMap { presRels[$0.prefixedAttr("id") ?? ""]?.target }.filter { !$0.isEmpty && zip.entry(named: $0) != nil }
        if paths.isEmpty {
            func n(_ p: String) -> Int { Int(p.filter(\.isNumber)) ?? 0 }
            paths = zip.entries.map(\.name).filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") && !$0.dropFirst(11).contains("/") }.sorted { n($0) < n($1) }
        }
        if let sz = pres.first("sldSz"), let cx = Double(sz.attr("cx") ?? ""), let cy = Double(sz.attr("cy") ?? ""), cx > 0, cy > 0 { aspect = cx / cy }
        for (i, path) in paths.enumerated() {
            slides.append(try readSlide(path: path, number: i + 1))
        }
    }

    // MARK: Text

    /// One paragraph's text: runs, line breaks and fields (slide number and date fields are left out).
    static func paragraphText(_ p: XNode) -> String {
        var s = ""
        for c in p.children {
            switch c.name {
            case "r": s += c.first("t")?.text ?? ""
            case "br": s += "\n"
            case "fld":
                let type = (c.attr("type") ?? "").lowercased()
                if !type.hasPrefix("slidenum") && !type.hasPrefix("datetime") { s += c.first("t")?.text ?? "" }
            default: break
            }
        }
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        // Spaces and tabs before a line break go; trailing whitespace goes.
        s = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = Substring(line)
            while let last = l.last, last == " " || last == "\t" { l = l.dropLast() }
            return String(l)
        }.joined(separator: "\n")
        while let last = s.last, last.isWhitespace { s.removeLast() }
        let lvl = Int(p.first("pPr")?.attr("lvl") ?? "") ?? 0
        if lvl >= 1, !s.trimmed.isEmpty { return "– " + String(s.drop(while: \.isWhitespace)) }
        return s
    }

    /// One per line; blank paragraphs collapse to one blank line; none at the start or end.
    static func joinParagraphs(_ paras: [String]) -> String {
        var lines: [String] = []
        for p in paras {
            let t = p.trimmed.isEmpty ? "" : p
            if t.isEmpty && (lines.isEmpty || lines.last == "") { continue }
            lines.append(t)
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private static func txBodyParagraphs(_ sp: XNode) -> [String] {
        guard let body = sp.child("txBody") else { return [] }
        return body.kids("p").map(paragraphText)
    }

    // MARK: Shape tree

    struct Collected {
        var title: [String] = []
        var body: [String] = []
        var blocks: [(paras: [String], isTextBox: Bool)] = []
        var pictures: [PPTXPicture] = []
        var mediaRids: [String] = []
        var hasChartOrDiagram = false
    }

    private static let skipPlaceholders: Set<String> = ["sldNum", "dt", "ftr", "hdr", "sldImg"]

    private static func xfrmArea(_ el: XNode) -> Int {
        guard let ext = el.first("ext") else { return 0 }
        let cx = Int(ext.attr("cx") ?? "") ?? 0, cy = Int(ext.attr("cy") ?? "") ?? 0
        return cx > 0 && cy > 0 ? cx * cy : 0
    }

    private static func addPicture(_ out: inout Collected, _ rels: [String: Rel], rid: String?, area: Int) {
        guard let rid, let rel = rels[rid], !rel.external else { return }
        let e = ext(of: rel.target)
        if !out.pictures.contains(where: { $0.path == rel.target }) {
            out.pictures.append(PPTXPicture(path: rel.target, ext: e, supported: pictureExt.contains(e), area: area))
        }
    }

    /// Walks a shape tree in document order (PowerPoint's stacking order, normally creation order).
    private static func walk(_ tree: XNode, _ rels: [String: Rel], _ out: inout Collected) {
        for node in tree.children {
            switch node.name {
            case "sp":
                let ph = node.first("ph")
                let phType = ph.map { $0.attr("type") ?? "body" } ?? ""
                if skipPlaceholders.contains(phType) { break }
                if let spPr = node.child("spPr"), let fill = spPr.first("blip") { addPicture(&out, rels, rid: fill.prefixedAttr("embed"), area: xfrmArea(spPr)) }
                let paras = txBodyParagraphs(node)
                if !paras.contains(where: { !$0.trimmed.isEmpty }) { break }
                if phType == "title" || phType == "ctrTitle" { out.title += paras }
                else if ph != nil { out.body += paras }
                else { out.blocks.append((paras, true)) }
            case "grpSp":
                walk(node, rels, &out)
            case "pic":
                let nvPr = node.first("nvPr")
                let mediaEls = ["videoFile", "audioFile", "media"].compactMap { nvPr?.first($0) }
                if nvPr != nil, !mediaEls.isEmpty {
                    for e in mediaEls {
                        if let rid = e.prefixedAttr("link") ?? e.prefixedAttr("embed"), !rid.isEmpty { out.mediaRids.append(rid) }
                    }
                    break   // its picture is only the poster frame
                }
                if let blip = node.first("blip") {
                    addPicture(&out, rels, rid: blip.prefixedAttr("embed"), area: node.child("spPr").map(xfrmArea) ?? 0)
                }
            case "graphicFrame":
                let uri = node.first("graphicData")?.attr("uri") ?? ""
                if uri.hasSuffix("/chart") || uri.hasSuffix("/diagram") { out.hasChartOrDiagram = true }
                let rows: [String] = node.all("tr").map { tr in
                    tr.kids("tc").map { tc in
                        let ps = (tc.first("txBody") ?? tc).kids("p").map(paragraphText)
                        return joinParagraphs(ps).replacingOccurrences(of: "\n", with: " ")
                    }.filter { !$0.isEmpty }.joined(separator: " | ")
                }
                if rows.contains(where: { !$0.isEmpty }) { out.blocks.append((rows, false)) }
            case "AlternateContent":
                if let choice = node.child("Choice") ?? node.child("Fallback") { walk(choice, rels, &out) }
            default: break
            }
        }
    }

    struct ParsedSlide {
        var title: String
        var body: String
        var pictures: [PPTXPicture]
        var bgPicture: PPTXPicture?
        var mediaRids: [String]
        var hidden: Bool
        var hasChartOrDiagram: Bool
    }

    /// Text and pictures of one slide's XML (pure: no zip access).
    static func parseSlide(_ root: XNode, rels: [String: Rel]) -> ParsedSlide {
        var out = Collected()
        if let tree = root.first("spTree") { walk(tree, rels, &out) }
        var bg: PPTXPicture?
        if let bgEl = root.first("bg"), let blip = bgEl.first("blip") {
            var tmp = Collected()
            addPicture(&tmp, rels, rid: blip.prefixedAttr("embed"), area: 0)
            bg = tmp.pictures.first
        }
        // The first text box becomes the title when there is no title placeholder, it is a single short line, and other text exists.
        var blocks = out.blocks
        var titleParas = out.title
        if titleParas.isEmpty, blocks.count + (out.body.isEmpty ? 0 : 1) > 1 {
            let first = blocks[0]
            let lines = first.paras.filter { !$0.trimmed.isEmpty }
            if lines.count == 1, lines[0].count <= 80, !lines[0].contains("\n"), first.isTextBox {
                titleParas = lines
                blocks.removeFirst()
            }
        }
        var bodyParas: [String] = []
        func addBlock(_ paras: [String]) {
            if let last = bodyParas.last, last != "" { bodyParas.append("") }
            bodyParas += paras
        }
        if !out.body.isEmpty { addBlock(out.body) }
        for b in blocks { addBlock(b.paras) }
        return ParsedSlide(title: joinParagraphs(titleParas.map { $0.replacingOccurrences(of: "\n", with: " ") }), body: joinParagraphs(bodyParas),
                           pictures: out.pictures, bgPicture: bg, mediaRids: out.mediaRids, hidden: root.attr("show") == "0",
                           hasChartOrDiagram: out.hasChartOrDiagram)
    }

    /// Speaker notes: the text of the notes page's body placeholder (not the slide image, slide number or footer).
    static func parseNotes(_ root: XNode) -> String {
        var paras: [String] = []
        for sp in root.all("sp") {
            guard let ph = sp.first("ph"), (ph.attr("type") ?? "body") == "body" else { continue }
            paras += txBodyParagraphs(sp)
        }
        return joinParagraphs(paras)
    }

    private func media(from slideRels: [String: Rel], wanted: Set<String>) -> [PPTXMedia] {
        var out: [PPTXMedia] = []
        var seen = Set<String>()
        // Dictionary order is random; keep results stable by sorting relationship ids naturally.
        for id in slideRels.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let rel = slideRels[id]!
            let t = rel.type.split(separator: "/").last.map(String.init) ?? ""
            guard t == "video" || t == "audio" || t == "media" else { continue }
            if !wanted.isEmpty, !wanted.contains(id), t == "media" { continue }
            if rel.external {
                if !seen.contains(rel.target) { out.append(PPTXMedia(path: "", kind: .video, ext: "", size: nil, supported: false, external: rel.target)) }
                seen.insert(rel.target)
                continue
            }
            if seen.contains(rel.target) { continue }
            let e = Self.ext(of: rel.target)
            let kind: PPTXMedia.Kind?
            if Self.videoExt.contains(e) || ["wmv", "avi", "mpg", "mpeg", "mkv"].contains(e) { kind = .video }
            else if Self.audioExt.contains(e) || ["wma", "mid", "midi"].contains(e) { kind = .audio }
            else { kind = nil }
            guard let kind else { continue }
            seen.insert(rel.target)
            let size = zip.entry(named: rel.target).map { Int64($0.uncompressedSize) }
            out.append(PPTXMedia(path: rel.target, kind: kind, ext: e, size: size, supported: (kind == .video ? Self.videoExt : Self.audioExt).contains(e), external: nil))
        }
        return out
    }

    private func readSlide(path: String, number: Int) throws -> PPTXSlide {
        let root = try xml(path) ?? XNode(name: "sld", attrs: [:])
        let slideRels = try rels(forPart: path)
        let parsed = Self.parseSlide(root, rels: slideRels)
        var notes = ""
        for rel in slideRels.values where rel.type.hasSuffix("/notesSlide") {
            if let nx = try? xml(rel.target) { notes = Self.parseNotes(nx) }
        }
        let mediaList = media(from: slideRels, wanted: Set(parsed.mediaRids))
        let hasText = !parsed.title.isEmpty || !parsed.body.isEmpty
        let kind: PPTXSlide.Kind = hasText ? .text : (!parsed.pictures.isEmpty || parsed.bgPicture != nil ? .picture : .empty)
        return PPTXSlide(number: number, path: path, hidden: parsed.hidden, title: parsed.title, body: parsed.body, notes: notes,
                         pictures: parsed.pictures, bgPicture: parsed.bgPicture, media: mediaList, kind: kind, hasChartOrDiagram: parsed.hasChartOrDiagram)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
