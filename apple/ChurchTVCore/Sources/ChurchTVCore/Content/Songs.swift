import Foundation

/// One section of a library song: `{"id":"s1","label":"Verse 1","text":"line one\nline two"}`.
public struct SongSection: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var text: String
    public init(id: String, label: String, text: String) { self.id = id; self.label = label; self.text = text }
}

/// A row of the shared song library (`songs`). Decode with `ContentJSON.decoder()`.
public struct Song: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var organizationId: UUID?
    public var title: String
    public var authors: String?
    public var ccliNumber: String?
    public var copyright: String?
    public var sections: [SongSection]
    /// Ordered section ids to play (repeats allowed). nil / empty = every section once, in order.
    public var arrangement: [String]?
    /// 0 = one slide per section. 0...12.
    public var linesPerSlide: Int
    public var source: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID, title: String, organizationId: UUID? = nil, authors: String? = nil, ccliNumber: String? = nil, copyright: String? = nil,
                sections: [SongSection] = [], arrangement: [String]? = nil, linesPerSlide: Int = 0, source: String? = nil,
                createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id; self.title = title; self.organizationId = organizationId; self.authors = authors; self.ccliNumber = ccliNumber
        self.copyright = copyright; self.sections = sections; self.arrangement = arrangement; self.linesPerSlide = linesPerSlide
        self.source = source; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, authors, copyright, sections, arrangement, source
        case organizationId = "organization_id", ccliNumber = "ccli_number", linesPerSlide = "lines_per_slide"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        organizationId = try c.decodeIfPresent(UUID.self, forKey: .organizationId)
        authors = try c.decodeIfPresent(String.self, forKey: .authors)
        ccliNumber = try c.decodeIfPresent(String.self, forKey: .ccliNumber)
        copyright = try c.decodeIfPresent(String.self, forKey: .copyright)
        sections = (try? c.decodeIfPresent([SongSection].self, forKey: .sections)) ?? []
        arrangement = (try? c.decodeIfPresent([String].self, forKey: .arrangement)) ?? nil
        linesPerSlide = (try? c.decodeIfPresent(Int.self, forKey: .linesPerSlide)) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// The TV-visible lyric slides (see `SongExpander`).
    public var lyricSlides: [LyricSlide] { SongExpander.expand(self) }
}

/// One lyric screen of a song.
public struct LyricSlide: Hashable, Sendable {
    public var label: String
    public var text: String
    public init(label: String, text: String) { self.label = label; self.text = text }
}

/// Port of `expandSong` in dashboard/src/songParsers.ts (the database function `song_expand()` is the truth for the TV; this mirrors it).
/// Follows the arrangement (unknown section ids are skipped, repeats allowed), splits sections into `linesPerSlide` lines,
/// and skips sections with no words.
public enum SongExpander {
    public static func expand(_ song: Song) -> [LyricSlide] {
        expand(sections: song.sections, arrangement: song.arrangement, linesPerSlide: song.linesPerSlide)
    }

    public static func expand(sections: [SongSection], arrangement: [String]?, linesPerSlide: Int) -> [LyricSlide] {
        let ids: [String] = (arrangement?.isEmpty == false) ? arrangement! : sections.map(\.id)
        var slides: [LyricSlide] = []
        for id in ids {
            guard let sec = sections.first(where: { $0.id == id }) else { continue }
            // JS: text.replace(/\r/g, '').replace(/^[\n ]+|[\n ]+$/g, '').split('\n')
            var text = sec.text.replacingOccurrences(of: "\r", with: "")
            let strip: Set<Character> = ["\n", " "]
            while let f = text.first, strip.contains(f) { text.removeFirst() }
            while let l = text.last, strip.contains(l) { text.removeLast() }
            let lines = text.components(separatedBy: "\n")
            // JS: lines.join('').trim() === ''
            if lines.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let n = linesPerSlide
            if n > 0 {
                var i = 0
                while i < lines.count {
                    slides.append(LyricSlide(label: sec.label, text: lines[i..<min(lines.count, i + n)].joined(separator: "\n")))
                    i += n
                }
            } else {
                slides.append(LyricSlide(label: sec.label, text: lines.joined(separator: "\n")))
            }
        }
        return slides
    }
}
