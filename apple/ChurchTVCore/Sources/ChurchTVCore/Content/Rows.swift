import Foundation

// Row models for the content tables and their editable "drafts". Decode rows with `ContentJSON.decoder()`.

/// A row of `playlists` (Kids) or `signage_playlists` (Signage). Which table is decided by the `PlaylistKind` the service call receives.
public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var organizationId: UUID
    /// nil = shared across the whole church.
    public var siteId: UUID?
    public var name: String
    public var items: [PlaylistItem]
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID = UUID(), organizationId: UUID, siteId: UUID? = nil, name: String, items: [PlaylistItem] = [], createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id; self.organizationId = organizationId; self.siteId = siteId; self.name = name; self.items = items
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case organizationId = "organization_id", siteId = "site_id", createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        organizationId = try c.decode(UUID.self, forKey: .organizationId)
        siteId = try c.decodeIfPresent(UUID.self, forKey: .siteId)
        name = try c.decode(String.self, forKey: .name)
        items = (try c.decodeIfPresent([PlaylistItem].self, forKey: .items)) ?? []
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public var itemCount: Int { items.count }
}

/// A row of `decks`.
public struct SlideDeck: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var organizationId: UUID
    public var siteId: UUID?
    public var name: String
    public var themeId: UUID?
    /// Deck default background (beats the theme's; a slide can override again).
    public var background: SlideBackground?
    public var slides: [DeckSlide]
    /// Start over after the last slide.
    public var loops: Bool
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID = UUID(), organizationId: UUID, siteId: UUID? = nil, name: String, themeId: UUID? = nil, background: SlideBackground? = nil,
                slides: [DeckSlide] = [], loops: Bool = false, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id; self.organizationId = organizationId; self.siteId = siteId; self.name = name; self.themeId = themeId
        self.background = background; self.slides = slides; self.loops = loops; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, background, slides, loops
        case organizationId = "organization_id", siteId = "site_id", themeId = "theme_id", createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        organizationId = try c.decode(UUID.self, forKey: .organizationId)
        siteId = try c.decodeIfPresent(UUID.self, forKey: .siteId)
        name = try c.decode(String.self, forKey: .name)
        themeId = try c.decodeIfPresent(UUID.self, forKey: .themeId)
        background = try? c.decodeIfPresent(SlideBackground.self, forKey: .background)
        slides = (try c.decodeIfPresent([DeckSlide].self, forKey: .slides)) ?? []
        loops = (try c.decodeIfPresent(Bool.self, forKey: .loops)) ?? false
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public var slideCount: Int { slides.count }
}

// MARK: - Write payloads (what insert/update send)

/// Body of an insert/update into `playlists` / `signage_playlists`. `site_id` is always written (null = all sites).
public struct PlaylistWrite: Encodable, Sendable {
    public var id: UUID?
    public var organizationId: UUID
    public var siteId: UUID?
    public var name: String
    public var items: [PlaylistItem]

    enum CodingKeys: String, CodingKey { case id, name, items, organizationId = "organization_id", siteId = "site_id" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(organizationId, forKey: .organizationId)
        try c.encode(siteId, forKey: .siteId)
        try c.encode(name, forKey: .name)
        try c.encode(items, forKey: .items)
    }
}

/// Body of an insert/update into `decks`.
public struct DeckWrite: Encodable, Sendable {
    public var id: UUID?
    public var organizationId: UUID
    public var siteId: UUID?
    public var name: String
    public var themeId: UUID?
    public var background: SlideBackground?
    public var slides: [DeckSlide]
    public var loops: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, background, slides, loops
        case organizationId = "organization_id", siteId = "site_id", themeId = "theme_id"
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(organizationId, forKey: .organizationId)
        try c.encode(siteId, forKey: .siteId)
        try c.encode(name, forKey: .name)
        try c.encode(themeId, forKey: .themeId)
        try c.encode(background, forKey: .background)
        try c.encode(slides, forKey: .slides)
        try c.encode(loops, forKey: .loops)
    }
}

/// Body of an insert/update into `slide_themes`.
public struct ThemeWrite: Encodable, Sendable {
    public var id: UUID?
    public var organizationId: UUID
    public var name: String
    public var config: ThemeConfig
    enum CodingKeys: String, CodingKey { case id, name, config, organizationId = "organization_id" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(organizationId, forKey: .organizationId)
        try c.encode(name, forKey: .name)
        try c.encode(config, forKey: .config)
    }
}

// MARK: - Drafts

/// The editable working copy of a Kids or Signage playlist. Editors mutate a draft, compare it with the value they started from
/// (`draft != original`) to know whether there are unsaved changes, and save it through `ContentService`.
/// New drafts get a client-made `id` and `isNew == true`; the service inserts with that id.
public struct PlaylistDraft: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var isNew: Bool
    public var organizationId: UUID
    public var siteId: UUID?
    public var name: String
    public var items: [PlaylistItem]

    public init(id: UUID = UUID(), isNew: Bool = true, organizationId: UUID, siteId: UUID? = nil, name: String = "", items: [PlaylistItem] = []) {
        self.id = id; self.isNew = isNew; self.organizationId = organizationId; self.siteId = siteId; self.name = name; self.items = items
    }
    public init(_ p: Playlist) { self.init(id: p.id, isNew: false, organizationId: p.organizationId, siteId: p.siteId, name: p.name, items: p.items) }

    /// The first thing wrong with the playlist for saving (website messages), or nil. Item numbers are 1-based.
    public func problem(kind: PlaylistKind) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the playlist a name." }
        for (i, item) in items.enumerated() {
            if let p = item.problem { return "Item \(i + 1) \(p)" }
        }
        return nil
    }

    /// Trimmed name; typed lyrics lose blank slides (what the website does on save).
    public func cleaned() -> PlaylistDraft {
        var d = self
        d.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        d.items = items.map { item in
            guard case .lyrics(var l) = item.content, !l.isLibrary else { return item }
            l.slides = l.slides.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return PlaylistItem(.lyrics(l), uid: item.uid)
        }
        return d
    }

    public func write(includeId: Bool) -> PlaylistWrite {
        let c = cleaned()
        return PlaylistWrite(id: includeId ? id : nil, organizationId: organizationId, siteId: siteId, name: c.name, items: c.items)
    }
}

/// The editable working copy of a deck (see `PlaylistDraft` for the conventions).
public struct DeckDraft: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var isNew: Bool
    public var organizationId: UUID
    public var siteId: UUID?
    public var name: String
    public var themeId: UUID?
    public var background: SlideBackground?
    public var slides: [DeckSlide]
    public var loops: Bool

    public init(id: UUID = UUID(), isNew: Bool = true, organizationId: UUID, siteId: UUID? = nil, name: String = "", themeId: UUID? = nil,
                background: SlideBackground? = nil, slides: [DeckSlide] = [], loops: Bool = false) {
        self.id = id; self.isNew = isNew; self.organizationId = organizationId; self.siteId = siteId; self.name = name
        self.themeId = themeId; self.background = background; self.slides = slides; self.loops = loops
    }
    public init(_ d: SlideDeck) {
        self.init(id: d.id, isNew: false, organizationId: d.organizationId, siteId: d.siteId, name: d.name, themeId: d.themeId,
                  background: d.background, slides: d.slides, loops: d.loops)
    }

    /// The first thing wrong with the deck for saving (`firstProblem` in render.ts), or nil.
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the deck a name." }
        if let b = background, (b.kind == .image || b.kind == .video), !b.isUsable {
            return "The deck background needs an image or video chosen (or switch it back to the theme background)."
        }
        for (i, s) in slides.enumerated() {
            if let p = s.problem { return "Slide \(i + 1): \(p)" }
        }
        return nil
    }

    public func cleaned() -> DeckDraft {
        var d = self
        d.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        d.slides = slides.map { $0.cleaned() }
        return d
    }

    public func write(includeId: Bool) -> DeckWrite {
        let c = cleaned()
        return DeckWrite(id: includeId ? id : nil, organizationId: organizationId, siteId: siteId, name: c.name, themeId: c.themeId,
                         background: c.background, slides: c.slides, loops: c.loops)
    }
}

/// What a Schedule sheet schedules: a deck (Slides) or a playlist (Kids or Signage).
public enum ScheduleTarget: Hashable, Identifiable, Sendable {
    case deck(id: UUID, name: String)
    case playlist(id: UUID, name: String, kind: PlaylistKind)

    public var id: UUID { switch self { case .deck(let id, _), .playlist(let id, _, _): return id } }
    public var name: String { switch self { case .deck(_, let n), .playlist(_, let n, _): return n } }
    public var module: AppModule { switch self { case .deck: return .slides; case .playlist(_, _, let k): return k.module } }
}
