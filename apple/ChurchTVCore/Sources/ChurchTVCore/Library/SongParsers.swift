import Foundation

// Port of dashboard/src/songParsers.ts: song import parsers (plain text, CCLI SongSelect .usr, ChordPro) and helpers.
// Pure code (no network), covered by SongParserTests. The database function `song_expand()` is the truth for the TV;
// `SongExpander.expand` (Songs.swift) mirrors it for previews.

/// What an importer found, ready to review and save as a `songs` row.
public struct ParsedSong: Equatable, Sendable {
    public var title = ""
    public var authors = ""
    public var ccliNumber = ""
    public var copyright = ""
    public var sections: [SongSection] = []
    public init() {}
}

/// Where a song came from (`songs.source`).
public enum SongSource: String, Sendable { case manual, paste, file }

/// A song being edited or imported: what `songs.insert` / `songs.update` writes.
public struct SongDraft: Equatable, Sendable {
    public var id: UUID?
    public var title: String
    public var authors: String
    public var ccliNumber: String
    public var copyright: String
    public var sections: [SongSection]
    /// nil = every section once, in order (the default).
    public var arrangement: [String]?
    public var linesPerSlide: Int
    public var source: String

    public init(id: UUID? = nil, title: String = "", authors: String = "", ccliNumber: String = "", copyright: String = "", sections: [SongSection] = [],
                arrangement: [String]? = nil, linesPerSlide: Int = 0, source: String = "manual") {
        self.id = id; self.title = title; self.authors = authors; self.ccliNumber = ccliNumber; self.copyright = copyright
        self.sections = sections; self.arrangement = arrangement; self.linesPerSlide = linesPerSlide; self.source = source
    }

    public init(_ song: Song) {
        self.init(id: song.id, title: song.title, authors: song.authors ?? "", ccliNumber: song.ccliNumber ?? "", copyright: song.copyright ?? "",
                  sections: song.sections, arrangement: song.arrangement, linesPerSlide: song.linesPerSlide, source: song.source ?? "manual")
    }

    public init(parsed: ParsedSong, source: SongSource) {
        self.init(title: parsed.title, authors: parsed.authors, ccliNumber: parsed.ccliNumber, copyright: parsed.copyright, sections: parsed.sections, source: source.rawValue)
    }

    /// Save check from SongEditor.tsx.
    public var problem: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the song a title." }
        if !sections.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "Add some words to at least one section." }
        return nil
    }

    /// An arrangement that is every section once, in order, is stored as null (the default); unknown ids are dropped.
    public var storedArrangement: [String]? {
        let known = Set(sections.map(\.id))
        let valid = arrangement?.filter { known.contains($0) } ?? []
        if valid.isEmpty { return nil }
        if valid.count == sections.count && zip(valid, sections).allSatisfy({ $0 == $1.id }) { return nil }
        return valid
    }

    /// The columns the website writes.
    public func row(organizationId: UUID) -> SongRow {
        SongRow(organizationId: organizationId, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                authors: authors.trimmingCharacters(in: .whitespacesAndNewlines).blankToNil, ccliNumber: ccliNumber.trimmingCharacters(in: .whitespacesAndNewlines).blankToNil,
                copyright: copyright.trimmingCharacters(in: .whitespacesAndNewlines).blankToNil,
                sections: sections.map { s in
                    var text = s.text
                    while let l = text.last, l.isWhitespace { text.removeLast() }
                    let label = s.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    return SongSection(id: s.id, label: label.isEmpty ? "Section" : label, text: text)
                },
                arrangement: storedArrangement, linesPerSlide: linesPerSlide, source: source)
    }

    /// "<title> (copy)" with the same words, like the website's Duplicate.
    public func duplicated() -> SongDraft { var d = self; d.id = nil; d.title = "\(title) (copy)"; return d }
}

/// Body of `songs.insert` / `songs.update`.
public struct SongRow: Encodable, Equatable, Sendable {
    public var organizationId: UUID
    public var title: String
    public var authors: String?
    public var ccliNumber: String?
    public var copyright: String?
    public var sections: [SongSection]
    public var arrangement: [String]?
    public var linesPerSlide: Int
    public var source: String

    enum CodingKeys: String, CodingKey {
        case title, authors, copyright, sections, arrangement, source
        case organizationId = "organization_id", ccliNumber = "ccli_number", linesPerSlide = "lines_per_slide"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(organizationId.uuidString.lowercased(), forKey: .organizationId)
        try c.encode(title, forKey: .title)
        try c.encode(authors, forKey: .authors)
        try c.encode(ccliNumber, forKey: .ccliNumber)
        try c.encode(copyright, forKey: .copyright)
        try c.encode(sections, forKey: .sections)
        try c.encode(arrangement, forKey: .arrangement)      // explicit null = default order
        try c.encode(linesPerSlide, forKey: .linesPerSlide)
        try c.encode(source, forKey: .source)
    }
}

public enum SongParsers {
    // MARK: Regex helpers

    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are literals in this file; a typo is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Capture groups of the first match (index 0 = whole match; unmatched groups are nil), or nil.
    private static func groups(_ r: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
    }

    private static func matches(_ r: NSRegularExpression, _ s: String) -> Bool { groups(r, s) != nil }

    private static func replace(_ r: NSRegularExpression, _ s: String, _ template: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    /// JS `string.split(regex)`: the pieces between matches.
    private static func splitRegex(_ r: NSRegularExpression, _ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var last = 0
        for m in r.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Section labels

    private static let labelWords = "verse|chorus|pre[\\s-]?chorus|bridge|tag|intro|outro|interlude|refrain|ending|instrumental|turnaround|vamp"
    private static let labelLine = rx("^\\s*[\\[(]?\\s*((?:\(labelWords))(?:\\s*\\d+)?)\\s*[\\])]?\\s*:?\\s*$", .caseInsensitive)

    /// "verse 1" -> "Verse 1", "pre chorus" -> "Pre-Chorus"; nil when the line is not a label.
    public static func labelFromLine(_ line: String) -> String? {
        guard let g = groups(labelLine, line), let raw = g[1] else { return nil }
        var s = raw.lowercased()
        s = replace(rx("pre[\\s-]?chorus"), s, "pre-chorus")
        s = replace(rx("([a-z])\\s*(\\d)"), s, "$1 $2")
        var out = ""
        var atStart = true
        for ch in s {
            if atStart, ch.isLetter, ch.isASCII { out += String(ch).uppercased() } else { out.append(ch) }
            atStart = ch == " " || ch == "-" || ch.isWhitespace
        }
        return out
    }

    // MARK: Helpers

    private static func normalise(_ text: String) -> String {
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        t = replace(rx("\r\n?"), t, "\n")
        t = t.components(separatedBy: "\n").map { replace(rx("[ \t\u{00A0}]+$"), $0, "") }.joined(separator: "\n")
        return replace(rx("\n{3,}"), t, "\n\n")
    }

    private static func stripNewlines(_ s: String) -> String {
        var t = Substring(s)
        while t.first == "\n" { t = t.dropFirst() }
        while t.last == "\n" { t = t.dropLast() }
        return String(t)
    }

    private static func withIds(_ parts: [(label: String, text: String)]) -> [SongSection] {
        parts.map { (label: trimmed($0.label), text: stripNewlines($0.text)) }
            .filter { !trimmed($0.text).isEmpty }
            .enumerated().map { SongSection(id: "s\($0.offset + 1)", label: $0.element.label, text: $0.element.text) }
    }

    private static let ccliLine = rx("^\\s*CCLI\\s+(?:Song\\s*)?(?:#|No\\.?|Number)\\s*:?\\s*(\\d{3,9})\\b", .caseInsensitive)
    private static let ccliLicenceLine = rx("^\\s*CCLI\\s+Licen[cs]e", .caseInsensitive)
    private static let copyrightLine = rx("^\\s*(?:©|\\(c\\)|copyright\\b)", .caseInsensitive)

    /// Splits lyric lines into sections: label lines start one, otherwise blank lines separate them.
    private static func splitSections(_ lines: [String]) -> [(label: String, text: String)] {
        var out: [(label: String, text: String)] = []
        var cur: (label: String?, lines: [String])?
        func flush() {
            if let c = cur, c.lines.contains(where: { !trimmed($0).isEmpty }) { out.append((c.label ?? "", c.lines.joined(separator: "\n"))) }
            cur = nil
        }
        for line in lines {
            if let label = labelFromLine(line) {
                flush(); cur = (label, [])
            } else if trimmed(line).isEmpty {
                flush()
            } else {
                if cur == nil { cur = (nil, []) }
                cur!.lines.append(line)
            }
        }
        flush()
        // Unlabelled sections are named by their position: Section 1, Section 2 ...
        return out.enumerated().map { (label: $0.element.label.isEmpty ? "Section \($0.offset + 1)" : $0.element.label, text: $0.element.text) }
    }

    // MARK: Plain text

    /// Plain pasted lyrics. `titleHint` is the title typed by the person; when empty, a first line that is not a label and is
    /// followed by a blank line becomes the title.
    public static func parsePlainText(_ raw: String, titleHint: String = "") -> ParsedSong {
        var song = ParsedSong()
        song.title = trimmed(titleHint)
        var copyright: [String] = []
        var lines: [String] = []
        for line in normalise(raw).components(separatedBy: "\n") {
            if let g = groups(ccliLine, line) {
                if song.ccliNumber.isEmpty { song.ccliNumber = g[1] ?? "" }
            } else if matches(ccliLicenceLine, line) {
                // a church licence number, not a song number: drop it from the lyrics
            } else if matches(copyrightLine, line) {
                copyright.append(trimmed(line))
            } else {
                lines.append(line)
            }
        }
        song.copyright = copyright.joined(separator: " ")
        while let f = lines.first, trimmed(f).isEmpty { lines.removeFirst() }
        if song.title.isEmpty, lines.count > 1, labelFromLine(lines[0]) == nil, trimmed(lines[1]).isEmpty {
            song.title = trimmed(lines[0])
            lines.removeFirst()
        }
        // Copyright/CCLI removal can leave runs of blank lines.
        let collapsed = replace(rx("\n{3,}"), lines.joined(separator: "\n"), "\n\n").components(separatedBy: "\n")
        song.sections = withIds(splitSections(collapsed))
        return song
    }

    // MARK: CCLI SongSelect .usr

    /// ASSUMPTION carried over from the website: the INI-like layout is reconstructed from memory of the classic ".usr" file and must be
    /// re-verified with a real SongSelect download. Tolerant: unknown keys are ignored, key case does not matter, and a file that is not
    /// INI-like is handed to the plain text parser.
    public static func parseUsr(_ raw: String, titleHint: String = "") -> ParsedSong {
        let text = normalise(raw)
        let looksIni = matches(rx("^\\s*\\[S\\s", [.caseInsensitive, .anchorsMatchLines]), text) || matches(rx("^\\s*(Words|Fields)\\s*=", [.caseInsensitive, .anchorsMatchLines]), text)
        if !looksIni { return parsePlainText(text, titleHint: titleHint) }

        var song = ParsedSong()
        var kv: [String: String] = [:]
        let header = rx("^\\s*\\[\\s*S\\s+A?(\\d+)\\s*\\]", .caseInsensitive)
        let pair = rx("^\\s*([^=\\[\\]]+?)\\s*=\\s*(.*)$")
        for line in text.components(separatedBy: "\n") {
            if let g = groups(header, line) { song.ccliNumber = g[1] ?? ""; continue }
            if let g = groups(pair, line), let k = g[1], let v = g[2] {
                kv[replace(rx("[\\s_#]+"), k.lowercased(), "")] = trimmed(v)
            }
        }
        if song.ccliNumber.isEmpty {
            // CCLISongID=, CCLI Song #=, CCLI=, CCLISongNumber= ...
            let digits = rx("\\d{3,9}")
            if let key = kv.keys.sorted().first(where: { $0.hasPrefix("ccli") && matches(digits, kv[$0] ?? "") }), let g = groups(digits, kv[key] ?? "") {
                song.ccliNumber = g[0] ?? ""
            }
        }
        song.title = trimmed(titleHint).isEmpty ? (kv["title"] ?? "") : trimmed(titleHint)
        let authors = kv["author"] ?? kv["authors"] ?? kv["writer"] ?? ""
        song.authors = splitRegex(rx("\\s*\\|\\s*|\\s*,\\s*"), authors).filter { !$0.isEmpty }.joined(separator: ", ")
        song.copyright = kv["copyright"] ?? ""

        let words = kv["words"] ?? ""
        let blocks: [String] = words.contains("/") ? words.components(separatedBy: "/t") : splitRegex(rx("\n\\s*\n"), words)
        let parts: [String] = blocks.map { block in
            let pieces = block.replacingOccurrences(of: "\n", with: "/").components(separatedBy: "/").map(trimmed)
            // keep an empty line only when it sits between two others (JS: l !== '' || (i > 0 && i < a.length - 1))
            let kept = pieces.enumerated().filter { !$0.element.isEmpty || ($0.offset > 0 && $0.offset < pieces.count - 1) }.map(\.element)
            return kept.joined(separator: "\n")
        }
        let fields = (kv["fields"] ?? "").components(separatedBy: "/").map(trimmed).filter { !$0.isEmpty }
        let useFields = fields.count == parts.count
        song.sections = withIds(parts.enumerated().map { (label: useFields ? fields[$0.offset] : "Section \($0.offset + 1)", text: $0.element) })
        return song
    }

    // MARK: ChordPro

    private static func unchord(_ line: String) -> String {
        trimmed(replace(rx("[ \t]{2,}"), replace(rx("\\[[^\\]]*\\]"), line, ""), " "))
    }

    /// ChordPro: directives for metadata and sections; inline chords like [G] or [Am7/C] are removed.
    public static func parseChordPro(_ raw: String, titleHint: String = "") -> ParsedSong {
        var song = ParsedSong()
        song.title = trimmed(titleHint)
        var authors: [String] = []
        var parts: [(label: String, text: String)] = []
        var cur: (label: String, lines: [String], block: Bool)?
        var skipping = false   // inside a chord/tab block
        func flush() {
            if let c = cur, c.lines.contains(where: { !trimmed($0).isEmpty }) { parts.append((c.label, c.lines.joined(separator: "\n"))) }
            cur = nil
        }
        func start(_ label: String, _ block: Bool) { flush(); cur = (label, [], block) }
        func addAuthor(_ a: String) { if !a.isEmpty && !authors.contains(a) { authors.append(a) } }
        let blocks: [String: String] = ["verse": "Verse", "chorus": "Chorus", "bridge": "Bridge", "sov": "Verse", "soc": "Chorus", "sob": "Bridge"]
        let directive = rx("^\\s*\\{\\s*([a-z_]+)\\s*(?::\\s*(.*?))?\\s*\\}\\s*$", .caseInsensitive)
        let comment = rx("^\\s*#")

        for line in normalise(raw).components(separatedBy: "\n") {
            if matches(comment, line) { continue }
            if let d = groups(directive, line) {
                let name = (d[1] ?? "").lowercased()
                let arg = trimmed(d[2] ?? "")
                if name == "title" || name == "t" {
                    if song.title.isEmpty { song.title = arg }
                } else if ["subtitle", "st", "artist", "author", "composer", "lyricist", "words", "music"].contains(name) {
                    addAuthor(arg)
                } else if name == "ccli" || name == "ccli_song" || name == "ccliid" {
                    song.ccliNumber = groups(rx("\\d{3,9}"), arg)?[0] ?? arg
                } else if name == "copyright" {
                    song.copyright = arg
                } else if name.hasPrefix("start_of_") || name == "sov" || name == "soc" || name == "sob" {
                    let kind = name.replacingOccurrences(of: "start_of_", with: "")
                    if let b = blocks[kind] { start(arg.isEmpty ? b : arg, true) }
                    else if kind == "tab" || kind == "grid" { flush(); skipping = true }
                    else { start(arg.isEmpty ? kind.prefix(1).uppercased() + kind.dropFirst() : arg, true) }
                } else if name.hasPrefix("end_of_") || name == "eov" || name == "eoc" || name == "eob" {
                    flush(); skipping = false
                } else if ["comment", "c", "comment_italic", "ci", "comment_box", "cb"].contains(name) {
                    if let label = labelFromLine(arg) { start(label, false) }
                }
                continue
            }
            if skipping { continue }
            if let label = labelFromLine(line) { start(label, false); continue }
            let text = unchord(line)
            if text.isEmpty {
                if let c = cur, !c.block { flush() }
                continue
            }
            if cur == nil { cur = ("", [], false) }
            cur!.lines.append(text)
        }
        flush()
        song.authors = authors.joined(separator: ", ")
        song.sections = withIds(parts.enumerated().map { (label: $0.element.label.isEmpty ? "Section \($0.offset + 1)" : $0.element.label, text: $0.element.text) })
        return song
    }

    // MARK: Files

    public static let fileExtensions = ["txt", "usr", "cho", "chordpro", "pro"]

    /// Picks a parser from the file name (and, for text, a quick look inside). The title falls back to the file name.
    public static func parseFile(name: String, text: String) -> (song: ParsedSong, kind: String) {
        let ext = (name as NSString).pathExtension.lowercased()
        var song: ParsedSong
        var kind = "plain text"
        if ext == "usr" { song = parseUsr(text); kind = "SongSelect" }
        else if ["cho", "chordpro", "pro", "crd", "chopro"].contains(ext)
                    || matches(rx("^\\s*\\{\\s*(title|t|start_of_\\w+|sov|soc)\\b", [.caseInsensitive, .anchorsMatchLines]), text) {
            song = parseChordPro(text); kind = "ChordPro"
        } else { song = parsePlainText(text) }
        if song.title.isEmpty {
            let base = (name as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
            song.title = trimmed(base)
        }
        return (song, kind)
    }

    /// Next unused section id: s1, s2 ... unique within the song.
    public static func newSectionId(_ sections: [SongSection]) -> String {
        let used = Set(sections.map(\.id))
        var n = sections.count + 1
        while used.contains("s\(n)") { n += 1 }
        return "s\(n)"
    }

    /// Reads a dropped or picked file as text: UTF-8, then UTF-16 (with BOM), then Windows Latin-1 (SongSelect exports are often not UTF-8).
    public static func decodeText(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Import planning (SongImport.tsx)

/// What to do with an imported song that has the same title as one already in the library.
public enum SongImportAction: String, CaseIterable, Sendable { case `import`, skip, replace, copy }

public enum SongImportPlanner {
    /// Case and spacing insensitive title (`norm` on the website).
    public static func norm(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The existing song with the same title, if any.
    public static func duplicate(of title: String, in library: [Song]) -> Song? {
        let n = norm(title)
        return n.isEmpty ? nil : library.first { norm($0.title) == n }
    }

    /// A duplicate is skipped by default; a new title is imported.
    public static func defaultAction(for title: String, in library: [Song]) -> SongImportAction { duplicate(of: title, in: library) == nil ? .import : .skip }

    /// Title written for a "copy" import of a duplicate.
    public static func copyTitle(_ title: String) -> String { "\(title.trimmingCharacters(in: .whitespacesAndNewlines)) (copy)" }
}
