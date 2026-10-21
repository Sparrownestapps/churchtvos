import Foundation
import ChurchTVCore

// Pure logic of the playlist editor (no UI), so it can be unit tested. Mirrors dashboard/src/pages/PlaylistsPage.tsx,
// SignagePlaylistsPage.tsx, LyricsItem.tsx, YouTubeItem.tsx and StreamItem.tsx.

enum PlaylistEditing {
    /// The blank item the website's Add buttons create. Signage streams start at 30 seconds, Signage signs use the church colour.
    static func newItem(_ type: PlaylistItem.TypeName, kind: PlaylistKind, churchName: String = "", branding: OrgBranding? = nil) -> PlaylistItem {
        switch (type, kind) {
        case (.stream, .signage): return PlaylistItem.newStream(seconds: 30)
        default:
            return PlaylistItem.new(type, kind: kind, churchName: churchName, youtubeChannelId: branding?.youtubeChannelId, signBackground: branding?.primaryColor)
        }
    }

    /// A copy with a new identity (new `uid`) that is otherwise identical, including unknown keys.
    static func duplicate(_ item: PlaylistItem) -> PlaylistItem { PlaylistItem(item.content) }

    /// Inserts the copy right after the original.
    /// `allowNdi` is false for a church without the NDI flag: the server refuses a second NDI entry there.
    static func duplicate(at index: Int, in items: inout [PlaylistItem], allowNdi: Bool = true) {
        guard items.indices.contains(index), allowNdi || items[index].typeName != .ndi else { return }
        items.insert(duplicate(items[index]), at: index + 1)
    }

    /// Same semantics as `Array.move(fromOffsets:toOffset:)` without importing SwiftUI.
    static func moved(_ items: [PlaylistItem], from source: IndexSet, to destination: Int) -> [PlaylistItem] {
        let moving = source.sorted().compactMap { items.indices.contains($0) ? items[$0] : nil }
        let before = source.filter { $0 < destination }.count
        var rest = items
        for i in source.sorted().reversed() where rest.indices.contains(i) { rest.remove(at: i) }
        let at = min(max(0, destination - before), rest.count)
        rest.insert(contentsOf: moving, at: at)
        return rest
    }

    // MARK: Validation / state

    /// Save is enabled when something changed and the draft is valid.
    static func canSave(draft: PlaylistDraft, original: PlaylistDraft, kind: PlaylistKind) -> Bool {
        (draft != original || draft.isNew) && draft.problem(kind: kind) == nil
    }

    /// Unsaved changes. A new draft counts as changed only once something was typed or added, so backing out of an empty one is free.
    static func hasChanges(draft: PlaylistDraft, original: PlaylistDraft) -> Bool { draft != original }

    // MARK: Duration

    /// Known seconds an item takes on screen, or nil when it depends on the media, the viewer pressing Next or the song.
    static func knownSeconds(_ item: PlaylistItem) -> Int? {
        switch item.content {
        case .image(let c): return c.seconds
        case .sign(let s): return s.seconds
        case .stream(let s): return s.seconds
        case .ndi(let n): return n.ndi.seconds
        case .countdown(let c):
            let s = c.countdown
            return s.effectiveMode == .duration && s.effectiveAtZero == .next ? s.seconds : nil
        default: return nil
        }
    }

    /// Sum of the known durations and how many items have no known length.
    static func totalSeconds(_ items: [PlaylistItem]) -> (seconds: Int, unknown: Int) {
        var total = 0, unknown = 0
        for i in items { if let s = knownSeconds(i) { total += s } else { unknown += 1 } }
        return (total, unknown)
    }

    static func durationText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let m = seconds / 60, s = seconds % 60
        if m < 60 { return s == 0 ? "\(m) min" : "\(m) min \(s) s" }
        return "\(m / 60) h \(m % 60) min"
    }

    /// "5 items · 1 min 20 s + 3 with no set length"
    static func summary(_ items: [PlaylistItem]) -> String {
        var parts = ["\(items.count) \(items.count == 1 ? "item" : "items")"]
        let t = totalSeconds(items)
        if t.seconds > 0 { parts.append(t.unknown > 0 ? "about \(durationText(t.seconds)) timed" : durationText(t.seconds)) }
        if t.unknown > 0, !items.isEmpty { parts.append("\(t.unknown) with no set length") }
        return parts.joined(separator: " · ")
    }

    /// Row title and one-line detail for the items list.
    static func rowText(_ item: PlaylistItem, songs: SongLookup, kind: PlaylistKind) -> (title: String, detail: String) {
        func blank(_ s: String, _ d: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? d : s }
        switch item.content {
        case .video(let c): return (blank(c.title, "Choose a video"), "Video" + (c.url.isEmpty ? " · needs a file" : " · plays to the end"))
        case .image(let c):
            let wait = c.seconds.map { "\($0) s" } ?? "until Next"
            return (blank(c.title, "Choose an image"), "Image" + (c.url.isEmpty ? " · needs a file" : " · \(wait)"))
        case .countdown(let c):
            let s = c.countdown
            let when = s.effectiveMode == .until ? "to \(SlideRender.clock12(s.until ?? "09:00"))" : SlideRender.countdownText(s.effectiveSeconds)
            return (blank(s.title ?? "", "Countdown"), "Countdown · \(when)")
        case .lyrics(let l):
            var title = l.title
            var count = l.slides.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            if let id = l.songId, let song = songs[id.lowercased()] { title = song.title; count = SongExpander.expand(song).count }
            let detail = l.isLibrary ? "Lyrics · library · \(count) \(count == 1 ? "slide" : "slides")" : "Lyrics · typed · \(count) \(count == 1 ? "slide" : "slides")"
            return (blank(title, "Lyrics"), detail)
        case .youtube(let y):
            let live = (y.videoId ?? "").isEmpty && !(y.channelId ?? "").isEmpty
            return (blank(y.title, live ? "Live now" : "Choose a YouTube video"), live ? "YouTube · live now" : "YouTube")
        case .sign(let s): return (blank(s.title, "Sign"), "Sign · \(s.seconds) s")
        case .stream(let s): return (blank(s.title, "Live stream"), "Live stream · " + (s.seconds.map { "\($0) s" } ?? "until Next"))
        case .ndi(let n): return (n.ndi.label, "NDI · experimental · " + (n.ndi.seconds.map { "\($0) s" } ?? "until Next"))
        case .unknown(let u): return ("Unknown item (\(u.typeName))", "Made by a newer app. Kept as it is.")
        }
    }
}

// MARK: - Lyrics source switching

/// Remembers the other source while the user flips between "From song library" and "Typed lyrics" (LyricsItem.tsx `stash`).
struct LyricsStash: Equatable {
    var slides: [String] = []
    var typedTitle = ""
    var songId = ""
    var songTitle = ""

    init(_ item: LyricsItem) {
        if let id = item.songId { songId = id; songTitle = item.title } else { slides = item.slides; typedTitle = item.title }
    }

    /// Switches `item` to the library (`toLibrary`) or to typed lyrics, restoring what was stashed. Unknown keys and show_title stay.
    mutating func switched(_ item: LyricsItem, toLibrary: Bool) -> LyricsItem {
        guard toLibrary != item.isLibrary else { return item }
        var out = item
        if item.isLibrary {
            songId = item.songId ?? ""; songTitle = item.title
            out.songId = nil; out.slides = slides; out.title = typedTitle
        } else {
            slides = item.slides; typedTitle = item.title
            out.songId = songId; out.slides = []; out.title = songTitle
        }
        return out
    }
}

// MARK: - YouTube

enum YouTubeLink {
    /// Accepts watch, youtu.be, /live/, /embed/ and /shorts/ links, or a bare 11-character id (`parseYouTubeId`).
    static func parseId(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func isId(_ s: String) -> Bool { s.count == 11 && s.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "_" || $0 == "-" } }
        if isId(text) { return text }
        guard let url = URL(string: text), let host = url.host?.lowercased(), host.contains(".") else { return nil }
        if host.hasSuffix("youtu.be") {
            let id = String(url.path.dropFirst().prefix(11))
            return id.isEmpty ? nil : id
        }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty { return v }
        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { ["live", "embed", "shorts"].contains($0) }), i + 1 < parts.count {
            let id = String(parts[i + 1].prefix(11))
            return isId(id) ? id : nil
        }
        return nil
    }

    static func thumbnail(_ id: String) -> URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }

    /// 750 -> "12:30", 3750 -> "1:02:30", nil/0 -> ""
    static func startText(_ seconds: Int?) -> String {
        guard let s = seconds, s > 0 else { return "" }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s % 60) : String(format: "%d:%02d", m, s % 60)
    }

    /// "12:30" -> 750, "90" -> 90, "" or junk -> nil
    static func parseStart(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.contains(where: { $0 == nil || $0! < 0 }), parts.count <= 3 else { return nil }
        let total = parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        return total > 0 ? total : nil
    }
}

// MARK: - Live stream

enum StreamLink {
    /// The save rule (same as the website): an http(s) link without spaces.
    static func isValid(_ url: String) -> Bool { StreamItem.isValidURL(url) }
    /// The editor asks for https:// (TVs and browsers block plain http streams on most networks).
    static func isSecure(_ url: String) -> Bool { url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("https://") }

    /// What to tell the person about the link while they type, or nil.
    static func hint(_ url: String) -> String? {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if !isValid(t) { return "Paste a full link starting with https://" }
        if !isSecure(t) { return "This link starts with http://. Most TVs only play https:// streams. Use the https:// version if there is one." }
        return nil
    }

    enum TestResult: Equatable {
        case ok(String), hint(String)
        var text: String { switch self { case .ok(let t), .hint(let t): return t } }
        var isOK: Bool { if case .ok = self { return true }; return false }
    }

    /// Reads the first bytes of the answer (`evaluate` in StreamItem.tsx): an HLS playlist starts with #EXTM3U.
    static func evaluate(status: Int, body: String) -> TestResult {
        if !(200..<300).contains(status) { return .hint("The server answered \(status). Check the link, and that the broadcast is live.") }
        if body.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") {
            return .ok("The link answered and looks like an HLS stream.")
        }
        return .hint("The link answered, but it doesn't look like an .m3u8 stream playlist. Double-check you copied the M3U8 link.")
    }

    static let unreachableText = "Couldn't check this link from the phone. That's common (the server may block checks, or the stream isn't live yet) and doesn't mean it's broken. The TV may still play it."

    static func test(_ url: String, session: URLSession = .shared) async -> TestResult {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(t), let u = URL(string: t) else { return .hint("Paste a full link starting with https:// first.") }
        var request = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            return evaluate(status: status, body: String(decoding: data.prefix(1024), as: UTF8.self))
        } catch {
            return .hint(unreachableText)
        }
    }
}

// MARK: - Typed lyrics

enum TypedLyrics {
    /// Number of slides that will be saved (blank ones are dropped on save).
    static func savedCount(_ slides: [String]) -> Int { slides.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    /// Splits pasted text at blank lines (what the website's textarea does).
    static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").reduce(into: [[String]()]) { acc, line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { acc.append([]) } else { acc[acc.count - 1].append(line) }
        }.map { $0.joined(separator: "\n") }.filter { !$0.isEmpty }
    }
}
