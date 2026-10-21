import Foundation

// Kids and Signage playlist items. The JSON must match PlaylistItem / SignageItem in dashboard/src/types.ts and the TV app (Model.kt).
// One Swift type serves both playlist kinds; `PlaylistKind.supports(_:)` says which item types a kind offers.
// Every payload keeps `extra`: the JSON keys it does not understand, written back unchanged on save.

/// Which playlist table / module.
public enum PlaylistKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case kids, signage
    public var id: String { rawValue }
    public var table: String { self == .kids ? "playlists" : "signage_playlists" }
    public var module: AppModule { self == .kids ? .kids : .signage }
    public var title: String { self == .kids ? "Kids playlist" : "Signage playlist" }
    /// Item types the website offers for this kind, in menu order.
    public var itemTypes: [PlaylistItem.TypeName] {
        switch self {
        case .kids: return [.video, .image, .countdown, .lyrics, .youtube, .stream]
        case .signage: return [.image, .video, .sign, .stream]
        }
    }
    public func supports(_ t: PlaylistItem.TypeName) -> Bool { itemTypes.contains(t) }
}

/// An image or video item. Kids video items have no `seconds` key; Signage ones write `seconds: null`; images always write it.
public struct MediaClip: Hashable, Sendable {
    public var title: String
    public var url: String
    public var mediaId: String
    /// Images: how long to show (nil = wait for Next in Kids). Videos play to the end.
    public var seconds: Int?
    /// Whether to write the `seconds` key when it is nil (as an explicit null).
    public var writesSeconds: Bool
    public var extra: RawObject

    public init(title: String = "", url: String = "", mediaId: String = "", seconds: Int? = nil, writesSeconds: Bool = true, extra: RawObject = [:]) {
        self.title = title; self.url = url; self.mediaId = mediaId; self.seconds = seconds; self.writesSeconds = writesSeconds; self.extra = extra
    }
    init(object: RawObject) {
        var o = object
        title = o.takeString("title") ?? ""
        url = o.takeString("url") ?? ""
        mediaId = o.takeString("media_id") ?? ""
        writesSeconds = o["seconds"] != nil
        seconds = o.takeInt("seconds")
        extra = o
    }
    func write(into o: inout RawObject) {
        o["title"] = .string(title); o["url"] = .string(url); o["media_id"] = .string(mediaId)
        if let seconds { o["seconds"] = .number(Double(seconds)) } else if writesSeconds { o["seconds"] = .null }
    }
    /// Fills url, id and title from a library file (what the website's picker does).
    public mutating func apply(_ m: MediaItem) { mediaId = m.id.uuidString.lowercased(); url = m.url; title = m.title }
}

/// A countdown (same settings as a Slides countdown slide).
public struct CountdownItem: Hashable, Sendable {
    public var countdown: CountdownSettings
    public var extra: RawObject
    public init(countdown: CountdownSettings = .new, extra: RawObject = [:]) { self.countdown = countdown; self.extra = extra }
}

/// Lyrics typed by hand (`slides`) or taken from the song library (`song_id`; the server expands it for the TV).
public struct LyricsItem: Hashable, Sendable {
    public var title: String
    /// Library song id (text). When non-nil the item is a library item and `slides` is ignored.
    public var songId: String?
    /// Typed lyrics, one string per slide.
    public var slides: [String]
    /// Show the song name as its own first slide that holds until Next (TV 1.3.0+).
    public var showTitle: Bool?
    public var extra: RawObject
    public var isLibrary: Bool { songId != nil }
    public init(title: String = "", songId: String? = nil, slides: [String] = [], showTitle: Bool? = false, extra: RawObject = [:]) {
        self.title = title; self.songId = songId; self.slides = slides; self.showTitle = showTitle; self.extra = extra
    }
}

/// YouTube video, or (videoId nil + channelId set) whatever the channel is live-streaming when the item plays.
public struct YouTubeItem: Hashable, Sendable {
    public var title: String
    public var videoId: String?
    public var channelId: String?
    public var start: Int?
    public var extra: RawObject
    public init(title: String = "", videoId: String? = nil, channelId: String? = nil, start: Int? = nil, extra: RawObject = [:]) {
        self.title = title; self.videoId = videoId; self.channelId = channelId; self.start = start; self.extra = extra
    }
}

public enum StreamFallback: String, Hashable, Sendable, CaseIterable { case skip, hold }

/// Live HLS (.m3u8) feed (TV app 1.1.0+).
public struct StreamItem: Hashable, Sendable {
    public var title: String
    public var url: String
    /// nil = until the viewer presses Next (Kids) / the playlist loops past it (Signage).
    public var seconds: Int?
    public var audio: Bool
    public var fallback: StreamFallback
    public var extra: RawObject
    public init(title: String = "", url: String = "", seconds: Int? = nil, audio: Bool = false, fallback: StreamFallback = .skip, extra: RawObject = [:]) {
        self.title = title; self.url = url; self.seconds = seconds; self.audio = audio; self.fallback = fallback; self.extra = extra
    }
    /// An http(s) link (same check as the website).
    public static func isValidURL(_ u: String) -> Bool {
        let t = u.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(where: \.isWhitespace) && t.count > 8
    }
}

/// A text-only sign slide (Signage, TV app 1.1.0+).
public struct SignItem: Hashable, Sendable {
    public var title: String
    public var subtext: String
    /// '#RRGGBB'
    public var background: String
    public var seconds: Int
    public var align: SlideAlign
    public var logo: Bool
    public var extra: RawObject
    public init(title: String = "", subtext: String = "", background: String = "#1f3a5f", seconds: Int = 10, align: SlideAlign = .center, logo: Bool = false, extra: RawObject = [:]) {
        self.title = title; self.subtext = subtext; self.background = background; self.seconds = seconds; self.align = align; self.logo = logo; self.extra = extra
    }
}

/// An item type this app does not know. The whole JSON object is kept and written back untouched.
public struct UnknownItem: Hashable, Sendable {
    public var raw: RawObject
    public init(raw: RawObject) { self.raw = raw }
    public var typeName: String { raw["type"]?.stringValue ?? "unknown" }
}

/// One entry of a Kids or Signage playlist.
public struct PlaylistItem: Identifiable, Hashable, Sendable, RawObjectCodable {
    public enum TypeName: String, Hashable, Sendable, CaseIterable {
        case video, image, countdown, lyrics, youtube, sign, stream
        public var label: String {
            switch self {
            case .video: return "Video"
            case .image: return "Image"
            case .countdown: return "Countdown"
            case .lyrics: return "Lyrics"
            case .youtube: return "YouTube"
            case .sign: return "Sign"
            case .stream: return "Live stream"
            }
        }
        public var symbol: String {
            switch self {
            case .video: return "film"
            case .image: return "photo"
            case .countdown: return "timer"
            case .lyrics: return "music.note.list"
            case .youtube: return "play.rectangle"
            case .sign: return "textformat"
            case .stream: return "dot.radiowaves.left.and.right"
            }
        }
    }

    public enum Content: Hashable, Sendable {
        case video(MediaClip), image(MediaClip), countdown(CountdownItem), lyrics(LyricsItem)
        case youtube(YouTubeItem), sign(SignItem), stream(StreamItem), unknown(UnknownItem)
    }

    /// Stable identity for lists and drag-to-reorder. Not stored in JSON, ignored by ==.
    public let uid: UUID
    public var content: Content
    public var id: UUID { uid }

    public init(_ content: Content, uid: UUID = UUID()) { self.content = content; self.uid = uid }

    public static func == (a: PlaylistItem, b: PlaylistItem) -> Bool { a.content == b.content }
    public func hash(into h: inout Hasher) { h.combine(content) }

    // MARK: Constructors that match the website's "Add" buttons

    public static func newVideo() -> PlaylistItem { .init(.video(MediaClip(writesSeconds: false))) }
    /// Kids images wait for Next (`seconds: nil`); Signage images default to 10 seconds.
    public static func newImage(seconds: Int? = nil) -> PlaylistItem { .init(.image(MediaClip(seconds: seconds))) }
    /// Signage video: has `seconds: null`.
    public static func newSignageVideo() -> PlaylistItem { .init(.video(MediaClip(writesSeconds: true))) }
    public static func newCountdown() -> PlaylistItem { .init(.countdown(CountdownItem())) }
    public static func newLyrics() -> PlaylistItem { .init(.lyrics(LyricsItem())) }
    public static func newYouTube(channelId: String?, churchName: String = "Live now") -> PlaylistItem {
        .init(.youtube(YouTubeItem(title: channelId != nil ? "\(churchName) · Live now" : "", channelId: channelId)))
    }
    public static func newStream(seconds: Int? = nil) -> PlaylistItem { .init(.stream(StreamItem(seconds: seconds))) }
    public static func newSign(background: String? = nil) -> PlaylistItem {
        .init(.sign(SignItem(background: ColorTools.isHex(background) ? background!.lowercased() : "#1f3a5f")))
    }
    /// The blank item the website adds for `type` in a playlist of `kind`.
    public static func new(_ type: TypeName, kind: PlaylistKind, churchName: String = "", youtubeChannelId: String? = nil, signBackground: String? = nil) -> PlaylistItem {
        switch type {
        case .video: return kind == .signage ? newSignageVideo() : newVideo()
        case .image: return newImage(seconds: kind == .signage ? 10 : nil)
        case .countdown: return newCountdown()
        case .lyrics: return newLyrics()
        case .youtube: return newYouTube(channelId: youtubeChannelId, churchName: churchName.isEmpty ? "Live now" : churchName)
        case .sign: return newSign(background: signBackground)
        case .stream: return newStream()
        }
    }

    // MARK: Info

    public var typeName: TypeName? {
        switch content {
        case .video: return .video
        case .image: return .image
        case .countdown: return .countdown
        case .lyrics: return .lyrics
        case .youtube: return .youtube
        case .sign: return .sign
        case .stream: return .stream
        case .unknown: return nil
        }
    }

    public var title: String {
        switch content {
        case .video(let c), .image(let c): return c.title
        case .countdown(let c): return c.countdown.title ?? ""
        case .lyrics(let l): return l.title
        case .youtube(let y): return y.title
        case .sign(let s): return s.title
        case .stream(let s): return s.title
        case .unknown(let u): return u.raw["title"]?.stringValue ?? ""
        }
    }

    /// What the problem is with this item for saving (website validation), or nil. `kind` only matters for sign items.
    public var problem: String? {
        switch content {
        case .video(let c): return c.url.isEmpty ? "needs a video chosen." : nil
        case .image(let c): return c.url.isEmpty ? "needs an image chosen." : nil
        case .countdown(let c): return c.countdown.problem
        case .lyrics(let l):
            if l.isLibrary && (l.songId ?? "").isEmpty { return "needs a song chosen from the library (or switch it to typed lyrics)." }
            return nil
        case .youtube(let y): return (y.videoId ?? "").isEmpty && (y.channelId ?? "").isEmpty ? "needs a YouTube video chosen." : nil
        case .sign(let s): return s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "needs a title." : nil
        case .stream(let s): return StreamItem.isValidURL(s.url) ? nil : "needs a stream link (starting with https://)."
        case .unknown: return nil
        }
    }

    // MARK: JSON

    public init(object: RawObject) {
        var o = object
        let type = o.takeString("type") ?? ""
        switch type {
        case "video": self.init(.video(MediaClip(object: o)))
        case "image": self.init(.image(MediaClip(object: o)))
        case "countdown":
            let s = CountdownSettings(consuming: &o)
            self.init(.countdown(CountdownItem(countdown: s, extra: o)))
        case "lyrics":
            let songId = o.takeString("song_id")
            let slides = o.takeStringArray("slides")
            let l = LyricsItem(title: o.takeString("title") ?? "", songId: songId, slides: slides ?? [], showTitle: o.takeBool("show_title"), extra: o)
            self.init(.lyrics(l))
        case "youtube":
            let y = YouTubeItem(title: o.takeString("title") ?? "", videoId: o.takeString("video_id"), channelId: o.takeString("channel_id"), start: o.takeInt("start"), extra: o)
            self.init(.youtube(y))
        case "sign":
            let s = SignItem(title: o.takeString("title") ?? "", subtext: o.takeString("subtext") ?? "", background: o.takeString("background") ?? "#1f3a5f",
                             seconds: o.takeInt("seconds") ?? 10, align: o.takeEnum("align") ?? .center, logo: o.takeBool("logo") ?? false, extra: o)
            self.init(.sign(s))
        case "stream":
            let s = StreamItem(title: o.takeString("title") ?? "", url: o.takeString("url") ?? "", seconds: o.takeInt("seconds"), audio: o.takeBool("audio") ?? false,
                               fallback: o.takeEnum("fallback") ?? .skip, extra: o)
            self.init(.stream(s))
        default:
            self.init(.unknown(UnknownItem(raw: object)))
        }
    }

    public var object: RawObject {
        switch content {
        case .video(let c):
            var o = c.extra; o["type"] = .string("video"); c.write(into: &o); return o
        case .image(let c):
            var o = c.extra; o["type"] = .string("image")
            var clip = c; clip.writesSeconds = true      // images always carry `seconds` (null = wait)
            clip.write(into: &o); return o
        case .countdown(let c):
            var o = c.extra; o["type"] = .string("countdown")
            var s = c.countdown; if s.title == nil { s.title = "" }
            s.write(into: &o); return o
        case .lyrics(let l):
            var o = l.extra; o["type"] = .string("lyrics"); o["title"] = .string(l.title)
            if let id = l.songId { o["song_id"] = .string(id); o["slides"] = nil } else { o["slides"] = .array(l.slides.map(RawJSON.string)); o["song_id"] = nil }
            o.put("show_title", l.showTitle); return o
        case .youtube(let y):
            var o = y.extra; o["type"] = .string("youtube"); o["title"] = .string(y.title)
            o["video_id"] = y.videoId.map(RawJSON.string) ?? .null
            o["channel_id"] = y.channelId.map(RawJSON.string) ?? .null
            o.putNullable("start", y.start); return o
        case .sign(let s):
            var o = s.extra; o["type"] = .string("sign"); o["title"] = .string(s.title); o["subtext"] = .string(s.subtext)
            o["background"] = .string(s.background); o["seconds"] = .number(Double(s.seconds))
            o["align"] = .string(s.align.rawValue); o["logo"] = .bool(s.logo); return o
        case .stream(let s):
            var o = s.extra; o["type"] = .string("stream"); o["title"] = .string(s.title); o["url"] = .string(s.url)
            o.putNullable("seconds", s.seconds); o["audio"] = .bool(s.audio); o["fallback"] = .string(s.fallback.rawValue); return o
        case .unknown(let u): return u.raw
        }
    }
}
