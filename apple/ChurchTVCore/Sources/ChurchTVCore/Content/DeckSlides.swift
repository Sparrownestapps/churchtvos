import Foundation

// Deck slides. The JSON must match dashboard/src/slidesTypes.ts (also read by the database function deck_expand() and the TV app).
// Keys the model does not understand are kept in `DeckSlide.extra` and written back unchanged.

public struct TextSlideContent: Hashable, Sendable {
    public var title: String?
    public var body: String?
    /// Default 'title_body'.
    public var layout: SlideLayout?
    /// Default from the theme.
    public var align: SlideAlign?
    /// '#RRGGBB', default from the theme.
    public var textColor: String?
    /// nil = waits for Next on the TV remote.
    public var seconds: Int?
    public init(title: String? = "", body: String? = "", layout: SlideLayout? = .titleBody, align: SlideAlign? = nil, textColor: String? = nil, seconds: Int? = nil) {
        self.title = title; self.body = body; self.layout = layout; self.align = align; self.textColor = textColor; self.seconds = seconds
    }
}

public struct MediaSlideContent: Hashable, Sendable {
    public var mediaId: String
    public var url: String
    public var mediaKind: MediaKind
    /// Default 'contain'.
    public var fit: ContentFit?
    /// Images only: auto-advance after N seconds; nil = wait. Videos advance when they end.
    public var seconds: Int?
    /// Videos only, default true.
    public var audio: Bool?
    public init(mediaId: String = "", url: String = "", mediaKind: MediaKind = .image, fit: ContentFit? = .contain, seconds: Int? = nil, audio: Bool? = true) {
        self.mediaId = mediaId; self.url = url; self.mediaKind = mediaKind; self.fit = fit; self.seconds = seconds; self.audio = audio
    }
    public mutating func apply(_ m: MediaItem) {
        mediaId = m.id.uuidString.lowercased(); url = m.url; mediaKind = m.kind == .video ? .video : .image
    }
}

public struct SongSlideContent: Hashable, Sendable {
    public var songId: String
    /// A styled title slide first; holds until Next.
    public var showTitle: Bool?
    public init(songId: String = "", showTitle: Bool? = false) { self.songId = songId; self.showTitle = showTitle }
}

public struct StreamSlideContent: Hashable, Sendable {
    public var title: String?
    public var url: String
    public var audio: Bool?
    public var fallback: StreamFallback?
    public var seconds: Int?
    public init(title: String? = "", url: String = "", audio: Bool? = false, fallback: StreamFallback? = .skip, seconds: Int? = nil) {
        self.title = title; self.url = url; self.audio = audio; self.fallback = fallback; self.seconds = seconds
    }
}

public struct BlankSlideContent: Hashable, Sendable {
    /// Default '#000000'.
    public var color: String?
    public init(color: String? = "#000000") { self.color = color }
}

/// One slide of a deck.
public struct DeckSlide: Identifiable, Hashable, Sendable, RawObjectCodable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case text, media, song, countdown, stream, ndi, blank
        /// Names as in the website's "Add slide" menu.
        public var name: String {
            switch self {
            case .text: return "Text"
            case .media: return "Image or video"
            case .song: return "Song"
            case .countdown: return "Countdown"
            case .stream: return "Live stream"
            case .ndi: return NdiText.label
            case .blank: return "Blank"
            }
        }
        public var symbol: String {
            switch self {
            case .text: return "textformat"
            case .media: return "photo.on.rectangle"
            case .song: return "music.note"
            case .countdown: return "timer"
            case .stream: return "dot.radiowaves.left.and.right"
            case .ndi: return "web.camera"
            case .blank: return "rectangle.fill"
            }
        }
    }

    public enum Content: Hashable, Sendable {
        case text(TextSlideContent)
        case media(MediaSlideContent)
        case song(SongSlideContent)
        case countdown(CountdownSettings)
        case stream(StreamSlideContent)
        /// EXPERIMENTAL NDI source (see Ndi.swift).
        case ndi(NdiSettings)
        case blank(BlankSlideContent)
        /// A kind this app does not know (written by a newer website). Kept untouched; only id/background/notes are editable.
        case unknown(kind: String)
    }

    /// Unique within the deck, like 's_k3f9a'.
    public var id: String
    /// Override for this slide only.
    public var background: SlideBackground?
    /// Private to the dashboard, never sent to the TV.
    public var notes: String?
    public var content: Content
    public var extra: RawObject

    public init(id: String, background: SlideBackground? = nil, notes: String? = nil, content: Content, extra: RawObject = [:]) {
        self.id = id; self.background = background; self.notes = notes; self.content = content; self.extra = extra
    }

    public var kind: Kind? {
        switch content {
        case .text: return .text
        case .media: return .media
        case .song: return .song
        case .countdown: return .countdown
        case .stream: return .stream
        case .ndi: return .ndi
        case .blank: return .blank
        case .unknown: return nil
        }
    }

    // MARK: New slides (blankSlide in render.ts)

    /// 's_' plus 5 random letters/digits, unique within the deck.
    public static func newId(existing: [DeckSlide]) -> String {
        let used = Set(existing.map(\.id))
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        while true {
            let id = "s_" + String((0..<5).map { _ in alphabet.randomElement()! })
            if !used.contains(id) { return id }
        }
    }

    public static func new(_ kind: Kind, existing: [DeckSlide]) -> DeckSlide {
        let id = newId(existing: existing)
        switch kind {
        case .text: return DeckSlide(id: id, content: .text(TextSlideContent()))
        case .media: return DeckSlide(id: id, content: .media(MediaSlideContent()))
        case .song: return DeckSlide(id: id, content: .song(SongSlideContent()))
        case .countdown: return DeckSlide(id: id, content: .countdown(.new))
        case .stream: return DeckSlide(id: id, content: .stream(StreamSlideContent()))
        case .ndi: return DeckSlide(id: id, content: .ndi(NdiSettings()))
        case .blank: return DeckSlide(id: id, content: .blank(BlankSlideContent()))
        }
    }

    /// A copy with a new id (for "Duplicate slide").
    public func duplicated(existing: [DeckSlide]) -> DeckSlide { var s = self; s.id = Self.newId(existing: existing); return s }

    // MARK: JSON

    public init(object: RawObject) {
        var o = object
        let kindName = o.takeString("kind") ?? ""
        id = o.takeString("id") ?? ""
        background = o.takeObject("background").map(SlideBackground.init(object:))
        notes = o.takeString("notes")
        switch kindName {
        case "text":
            content = .text(TextSlideContent(title: o.takeString("title"), body: o.takeString("body"), layout: o.takeEnum("layout"),
                                             align: o.takeEnum("align"), textColor: o.takeString("text_color"), seconds: o.takeInt("seconds")))
        case "media":
            content = .media(MediaSlideContent(mediaId: o.takeString("media_id") ?? "", url: o.takeString("url") ?? "",
                                               mediaKind: o.takeEnum("media_kind") ?? .image, fit: o.takeEnum("fit"),
                                               seconds: o.takeInt("seconds"), audio: o.takeBool("audio")))
        case "song":
            content = .song(SongSlideContent(songId: o.takeString("song_id") ?? "", showTitle: o.takeBool("show_title")))
        case "countdown":
            content = .countdown(CountdownSettings(consuming: &o))
        case "stream":
            content = .stream(StreamSlideContent(title: o.takeString("title"), url: o.takeString("url") ?? "", audio: o.takeBool("audio"),
                                                 fallback: o.takeEnum("fallback"), seconds: o.takeInt("seconds")))
        case "ndi":
            content = .ndi(NdiSettings(consuming: &o))
        case "blank":
            content = .blank(BlankSlideContent(color: o.takeString("color")))
        default:
            content = .unknown(kind: kindName)
        }
        extra = o
    }

    public var object: RawObject {
        var o = extra
        o["id"] = .string(id)
        o.put("notes", notes)
        if let background { o["background"] = .object(background.object) }
        switch content {
        case .text(let t):
            o["kind"] = .string("text")
            o.put("title", t.title); o.put("body", t.body); o.put("layout", t.layout); o.put("align", t.align); o.put("text_color", t.textColor)
            if let s = t.seconds { o["seconds"] = .number(Double(s)) } else { o["seconds"] = .null }
        case .media(let m):
            o["kind"] = .string("media")
            o["media_id"] = .string(m.mediaId); o["url"] = .string(m.url); o["media_kind"] = .string(m.mediaKind.rawValue)
            o.put("fit", m.fit); o.put("audio", m.audio)
            if let s = m.seconds { o["seconds"] = .number(Double(s)) } else { o["seconds"] = .null }
        case .song(let s):
            o["kind"] = .string("song")
            o["song_id"] = .string(s.songId); o.put("show_title", s.showTitle)
        case .countdown(let c):
            o["kind"] = .string("countdown")
            c.write(into: &o)
        case .stream(let s):
            o["kind"] = .string("stream")
            o.put("title", s.title); o["url"] = .string(s.url); o.put("audio", s.audio); o.put("fallback", s.fallback)
            if let sec = s.seconds { o["seconds"] = .number(Double(sec)) } else { o["seconds"] = .null }
        case .ndi(let n):
            o["kind"] = .string("ndi")
            n.write(into: &o, writesTitle: true)
        case .blank(let b):
            o["kind"] = .string("blank")
            o.put("color", b.color)
        case .unknown(let k):
            o["kind"] = .string(k)
        }
        return o
    }

    // MARK: Checks and cleanup (firstProblem / cleanSlide in render.ts)

    /// What is wrong with this slide for saving, or nil.
    public var problem: String? {
        if let b = background, (b.kind == .image || b.kind == .video), !b.isUsable { return "the background needs an image or video chosen." }
        switch content {
        case .media(let m): return m.url.isEmpty ? "needs an image or video chosen." : nil
        case .song(let s): return s.songId.isEmpty ? "needs a song chosen." : nil
        case .stream(let s): return StreamItem.isValidURL(s.url) ? nil : "needs a stream link starting with https://."
        case .countdown(let c): return c.problem
        case .ndi(let n): return n.problem
        case .text(let t):
            let empty = (t.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (t.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return empty ? "is an empty text slide. Add some words or delete it." : nil
        case .blank, .unknown: return nil
        }
    }

    /// Trims text, drops empty optional fields.
    public func cleaned() -> DeckSlide {
        var s = self
        if s.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { s.notes = nil }
        else { s.notes = s.notes?.trimmingCharacters(in: .whitespacesAndNewlines) }
        func trim(_ v: String?) -> String { (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        switch s.content {
        case .text(var t): t.title = trim(t.title); t.body = trim(t.body); s.content = .text(t)
        case .countdown(var c): c.title = trim(c.title); s.content = .countdown(c)
        case .stream(var st): st.title = trim(st.title); st.url = st.url.trimmingCharacters(in: .whitespacesAndNewlines); s.content = .stream(st)
        case .ndi(let n): s.content = .ndi(n.cleaned())
        default: break
        }
        return s
    }
}
