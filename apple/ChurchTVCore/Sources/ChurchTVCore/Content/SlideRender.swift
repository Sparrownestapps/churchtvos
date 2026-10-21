import Foundation

// Pure rules for drawing a slide, ported from dashboard/src/slides/render.ts (no UI, fully testable).
// All sizes are percent of the frame HEIGHT, so a landscape and a portrait frame of the same height draw text at the same size.

public enum SlideMetrics {
    public static let defaultNavy = "#1f3a5f"
    /// Text sizes at scale 1, as percent of frame height.
    public static let titlePct = 9.0
    public static let bodyPct = 6.0
    public static let labelPct = 2.6
    public static let smallPct = 3.0
    public static let countdownPct = 22.0
    /// Auto-fit never shrinks text below this.
    public static let minPct = 2.4
    /// Frame width as percent of frame height.
    public static let aspectLand = (16.0 / 9.0) * 100
    public static let aspectPort = (9.0 / 16.0) * 100
}

public enum FrameShape: Sendable { case landscape, portrait
    public var aspect: Double { self == .landscape ? SlideMetrics.aspectLand : SlideMetrics.aspectPort }
}

/// Theme config with every default filled in (what the TV does too).
public struct ResolvedTheme: Hashable, Sendable {
    public var font: ThemeFont
    public var titleScale: Double
    public var bodyScale: Double
    public var textColor: String
    public var align: SlideAlign
    public var position: TextPosition
    public var shadow: Bool
    public var outline: Bool
    public var margin: Double
    public var showLabels: Bool
    public var logo: ThemeLogo

    public init(_ c: ThemeConfig? = nil) {
        let t = c ?? ThemeConfig()
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
        font = t.font ?? .lato
        titleScale = clamp(t.titleScale ?? 1, 0.5, 1.5)
        bodyScale = clamp(t.bodyScale ?? 1, 0.5, 1.5)
        textColor = ColorTools.isHex(t.textColor) ? t.textColor! : "#FFFFFF"
        align = t.align ?? .center
        position = t.position ?? .center
        shadow = t.shadow ?? true
        outline = t.outline ?? false
        margin = clamp(t.margin ?? 8, 0, 20)
        showLabels = t.showLabels ?? true
        logo = t.logo ?? ThemeLogo()
    }
}

public extension ThemeConfig {
    var resolved: ResolvedTheme { ResolvedTheme(self) }
}

public enum BackgroundResolver {
    /// slide override, then deck, then theme, then the default colour. An image/video background with no file chosen is skipped.
    public static func resolve(slide: SlideBackground?, deck: SlideBackground?, theme: SlideBackground?, fallbackColor: String = SlideMetrics.defaultNavy) -> SlideBackground {
        for b in [slide, deck, theme] { if let b, b.isUsable { return b } }
        return .solid(fallbackColor)
    }

    /// The colours text sits on, with the dim overlay applied. Empty when it depends on a picture.
    public static func colors(_ bg: SlideBackground) -> [String] {
        let dim = bg.dim ?? 0
        switch bg.kind {
        case .color: return bg.color.map { [ColorTools.dimmed($0, dim)] } ?? []
        case .gradient: return [bg.color, bg.color2].compactMap { $0 }.map { ColorTools.dimmed($0, dim) }
        default: return []
        }
    }

    /// Worst contrast ratio of the text colour against a plain colour/gradient background; nil for pictures.
    public static func worstContrast(textColor: String, bg: SlideBackground) -> Double? {
        let cols = colors(bg).filter(ColorTools.isHex)
        guard !cols.isEmpty, ColorTools.isHex(textColor) else { return nil }
        return cols.map { ColorTools.contrast(textColor, $0) }.min()
    }
}

/// One screen of what the TV shows.
public enum PreviewFrame: Hashable, Sendable {
    case text(layout: SlideLayout, title: String, body: String, align: SlideAlign?, color: String?)
    case lyric(text: String, label: String, n: Int, count: Int)
    case songTitle(title: String, authors: String, ccli: String, copyright: String)
    case countdown(title: String, seconds: Int, until: String?)
    case media(url: String, kind: MediaKind, fit: ContentFit)
    case stream(title: String)
    case blank(color: String)
    /// A Signage text sign (drawn by `PlaylistItemPreview`, not by the theme text plan).
    case sign(SignItem)
}

public typealias SongLookup = [String: Song]
public extension Song {
    /// Songs by lowercase id text, the key deck slides and lyrics items use (`song_id`).
    static func lookup(_ songs: [Song]) -> SongLookup {
        Dictionary(songs.map { ($0.id.uuidString.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }
}

public enum SlideRender {
    /// The screens a deck slide produces. A song makes a title frame (if asked for) plus one frame per lyric slide.
    public static func frames(for slide: DeckSlide, songs: SongLookup) -> [PreviewFrame] {
        switch slide.content {
        case .text(let t):
            return [.text(layout: t.layout ?? .titleBody, title: t.title ?? "", body: t.body ?? "", align: t.align, color: t.textColor)]
        case .media(let m):
            return [.media(url: m.url, kind: m.mediaKind, fit: m.fit ?? .contain)]
        case .countdown(let c):
            let until = c.mode == .until && !(c.until ?? "").isEmpty ? c.until : nil
            return [.countdown(title: c.title ?? "", seconds: c.seconds ?? 0, until: until)]
        case .stream(let s):
            return [.stream(title: s.title ?? "")]
        case .blank(let b):
            return [.blank(color: b.color ?? "#000000")]
        case .unknown:
            return [.text(layout: .title, title: "Unknown slide", body: "This slide type needs a newer app.", align: nil, color: nil)]
        case .song(let s):
            guard let song = songs[s.songId.lowercased()] else {
                return [.text(layout: .title, title: s.songId.isEmpty ? "Choose a song" : "Song not in the library", body: "", align: nil, color: nil)]
            }
            let lyrics = SongExpander.expand(song)
            var out: [PreviewFrame] = []
            if s.showTitle == true {
                out.append(.songTitle(title: song.title, authors: song.authors ?? "", ccli: song.ccliNumber ?? "", copyright: song.copyright ?? ""))
            }
            for (i, l) in lyrics.enumerated() { out.append(.lyric(text: l.text, label: l.label, n: i + 1, count: lyrics.count)) }
            return out.isEmpty ? [.text(layout: .title, title: song.title, body: "(this song has no words yet)", align: nil, color: nil)] : out
        }
    }

    /// The screens a Kids or Signage playlist item produces (songs make a title frame when asked plus one frame per lyric slide).
    public static func frames(for item: PlaylistItem, songs: SongLookup) -> [PreviewFrame] {
        func text(_ title: String, _ body: String = "") -> [PreviewFrame] { [.text(layout: .title, title: title, body: body, align: nil, color: nil)] }
        switch item.content {
        case .video(let c): return c.url.isEmpty ? text("Choose a video") : [.media(url: c.url, kind: .video, fit: .contain)]
        case .image(let c): return c.url.isEmpty ? text("Choose an image") : [.media(url: c.url, kind: .image, fit: .contain)]
        case .countdown(let c):
            let s = c.countdown
            return [.countdown(title: s.title ?? "", seconds: s.seconds ?? 0, until: s.effectiveMode == .until && !(s.until ?? "").isEmpty ? s.until : nil)]
        case .youtube(let y): return text("YouTube", y.title)
        case .sign(let s): return [.sign(s)]
        case .stream(let s): return [.stream(title: s.title)]
        case .unknown(let u): return text("Unknown item", "A newer app can edit this (\(u.typeName)).")
        case .lyrics(let l):
            var words: [LyricSlide] = []
            var title = l.title
            if let id = l.songId {
                guard let song = songs[id.lowercased()] else { return text(id.isEmpty ? "Choose a song" : "Song not in the library") }
                title = song.title
                words = SongExpander.expand(song)
            } else {
                words = l.slides.map { LyricSlide(label: "", text: $0) }
            }
            var out: [PreviewFrame] = []
            if l.showTitle == true { out.append(.songTitle(title: title, authors: "", ccli: "", copyright: "")) }
            for (i, w) in words.enumerated() { out.append(.lyric(text: w.text, label: w.label, n: i + 1, count: words.count)) }
            return out.isEmpty ? text(title.isEmpty ? "Lyrics" : title, "(no words yet)") : out
        }
    }

    /// How many TV screens a song slide makes (title slide included).
    public static func songScreenCount(showTitle: Bool, song: Song?) -> Int {
        song.map { SongExpander.expand($0).count + (showTitle ? 1 : 0) } ?? 0
    }

    /// '09:00' -> '9:00 AM'
    public static func clock12(_ hhmm: String) -> String {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        let h = p.first ?? 0, m = p.count > 1 ? p[1] : 0
        return "\(h % 12 == 0 ? 12 : h % 12):" + String(format: "%02d", m) + " " + (h < 12 ? "AM" : "PM")
    }

    /// 300 -> '05:00', 3700 -> '1:01:40'
    public static func countdownText(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s % 60) : String(format: "%02d:%02d", m, s % 60)
    }

    // MARK: Text blocks and auto-fit

    public struct Block: Hashable, Sendable {
        public enum Role: Sendable { case label, title, body, small, time }
        public var role: Role
        public var text: String
        /// Percent of frame height, before shrinking.
        public var size: Double
        public var weight: Int
    }

    public struct TextPlan: Hashable, Sendable {
        public var blocks: [Block]
        public var align: SlideAlign
        public var color: String
        /// The box the text fits in, percent from the top of the frame.
        public var top: Double
        public var bottom: Double
    }

    /// Which blocks a frame draws, at what size, and the box (percent from the top) they fit in. nil for frames with no text (media, stream, blank).
    public static func planText(_ frame: PreviewFrame, theme t: ResolvedTheme) -> TextPlan? {
        let ts = SlideMetrics.titlePct * t.titleScale
        let bs = SlideMetrics.bodyPct * t.bodyScale
        let m = t.margin
        func box(_ position: TextPosition, lowerThird: Bool = false) -> (Double, Double) {
            if lowerThird { return (max(m, 66), 100 - m) }
            if position == .lower { return (max(m, 45), 100 - m) }
            if position == .top { return (m, min(100 - m, 55)) }
            return (m, 100 - m)
        }
        var blocks: [Block] = []
        func push(_ role: Block.Role, _ text: String, _ size: Double, _ weight: Int) {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(Block(role: role, text: text, size: size, weight: weight)) }
        }
        switch frame {
        case .text(let layout, let title, let body, let align, let color):
            if layout != .body { push(.title, title, ts, 800) }
            if layout != .title { push(.body, body, bs, 500) }
            let (top, bottom) = box(t.position, lowerThird: layout == .lowerThird)
            return TextPlan(blocks: blocks, align: align ?? t.align, color: ColorTools.isHex(color) ? color! : t.textColor, top: top, bottom: bottom)
        case .lyric(let text, let label, _, _):
            if t.showLabels { push(.label, label, SlideMetrics.labelPct, 700) }
            push(.title, text, ts, 700)
            let (top, bottom) = box(t.position)
            return TextPlan(blocks: blocks, align: t.align, color: t.textColor, top: top, bottom: bottom)
        case .songTitle(let title, let authors, let ccli, let copyright):
            push(.title, title, ts, 800)
            push(.small, authors, SlideMetrics.smallPct, 500)
            push(.small, copyright, SlideMetrics.smallPct * 0.85, 400)
            push(.small, ccli.isEmpty ? "" : "CCLI Song #\(ccli)", SlideMetrics.smallPct * 0.85, 400)
            let (top, bottom) = box(t.position)
            return TextPlan(blocks: blocks, align: t.align, color: t.textColor, top: top, bottom: bottom)
        case .countdown(let title, let seconds, let until):
            push(.body, title, bs, 600)
            if let until { push(.time, "Starts at \(clock12(until))", SlideMetrics.countdownPct * 0.45, 800) }
            else { push(.time, countdownText(seconds), SlideMetrics.countdownPct, 800) }
            return TextPlan(blocks: blocks, align: .center, color: t.textColor, top: m, bottom: 100 - m)
        case .media, .stream, .blank, .sign:
            return nil
        }
    }

    static let lineHeight = 1.2
    /// Average glyph width as a fraction of the font size (a little generous so the estimate errs on shrinking).
    static func glyph(_ font: ThemeFont, _ weight: Int) -> Double { (font == .julius ? 0.6 : 0.52) * (weight >= 700 ? 1.06 : 1) }

    /// Number of lines a text takes when wrapped at a width (percent-of-height units). Words longer than a line are broken.
    public static func wrapLines(_ text: String, size: Double, width: Double, charW: Double) -> Int {
        let perLine = max(1, Int((width / (size * charW)).rounded(.down)))
        var lines = 0
        for para in text.components(separatedBy: "\n") {
            var used = 0
            var n = 1
            for word in para.split(whereSeparator: { $0.isWhitespace }) {
                let w = word.utf16.count
                if w > perLine {
                    if used > 0 { n += 1 }
                    n += Int((Double(w) / Double(perLine)).rounded(.up)) - 1
                    used = (w % perLine == 0) ? perLine : w % perLine
                } else if used == 0 { used = w }
                else if used + 1 + w <= perLine { used += 1 + w }
                else { n += 1; used = w }
            }
            lines += n
        }
        return lines
    }

    /// Lowest shrink factor: the main text never goes below `minPct` (labels and small print do not limit it).
    public static func minScale(_ plan: TextPlan) -> Double {
        let main = plan.blocks.filter { $0.role != .label && $0.role != .small }.map(\.size)
        return main.isEmpty ? 1 : min(1, SlideMetrics.minPct / (main.min() ?? 1))
    }

    /// The shrink factor (0 to 1) that makes the text blocks fit the box: start at 1 and shrink by 5% steps until the wrapped
    /// height fits, never below `minScale`.
    public static func fitScale(_ plan: TextPlan, theme t: ResolvedTheme, shape: FrameShape) -> Double {
        if plan.blocks.isEmpty { return 1 }
        let boxW = shape.aspect * (1 - 2 * (t.margin / 100))
        let boxH = max(1, plan.bottom - plan.top)
        let kMin = minScale(plan)
        func height(_ k: Double) -> Double {
            var h = 0.0
            for (i, b) in plan.blocks.enumerated() {
                let size = b.size * k
                h += Double(wrapLines(b.text, size: size, width: boxW, charW: glyph(t.font, b.weight))) * size * lineHeight
                if i < plan.blocks.count - 1 { h += size * ((b.role == .title || b.role == .label) ? 0.3 : 0.15) }
            }
            return h
        }
        var k = 1.0
        while k > kMin && height(k) > boxH { k *= 0.95 }
        return max(kMin, (k * 1000).rounded() / 1000)
    }
}

// MARK: - TV outlines

/// One line of the "Jump to" list a TV reports (and what the remote shows).
public struct OutlineEntry: Hashable, Identifiable, Sendable {
    /// Position in the list (0-based, like `screen_status.slide_index`).
    public var index: Int
    public var label: String
    /// The deck slide it comes from (nil for playlists).
    public var slideId: String?
    public var id: Int { index }
}

/// The slide list a TV shows for a deck, labelled exactly like the TV app (`DeckSlide.listLabel()` in SlidesPlayer.kt):
/// songs become a "(title)" entry (when asked for) plus "Song · Verse 1" entries; songs missing from the library are skipped.
public enum DeckOutline {
    public static func entries(for slides: [DeckSlide], songs: SongLookup) -> [OutlineEntry] {
        var out: [OutlineEntry] = []
        func add(_ label: String, _ id: String) { out.append(OutlineEntry(index: out.count, label: label, slideId: id)) }
        func firstNonBlank(_ s: String?) -> String? { (s?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? s : nil }
        for slide in slides {
            switch slide.content {
            case .text(let t):
                let firstLine = t.body?.components(separatedBy: "\n").first
                add(firstNonBlank(t.title) ?? firstNonBlank(firstLine) ?? "Text", slide.id)
            case .media(let m): add(m.mediaKind == .video ? "Video" : "Picture", slide.id)
            case .countdown(let c): add(firstNonBlank(c.title).map { "Countdown: \($0)" } ?? "Countdown", slide.id)
            case .stream(let s): add(firstNonBlank(s.title).map { "Live: \($0)" } ?? "Live stream", slide.id)
            case .blank: add("Blank", slide.id)
            case .unknown: add("—", slide.id)
            case .song(let s):
                guard let song = songs[s.songId.lowercased()] else { continue }
                if s.showTitle == true { add("\(song.title) (title)", slide.id) }
                for (i, l) in SongExpander.expand(song).enumerated() {
                    add("\(song.title) · \(firstNonBlank(l.label) ?? "Part \(i + 1)")", slide.id)
                }
            }
        }
        return out
    }

    public static func labels(for slides: [DeckSlide], songs: SongLookup) -> [String] { entries(for: slides, songs: songs).map(\.label) }

    /// Every frame of the deck in TV order, with the slide each comes from (for stepping through a preview).
    public static func frames(for slides: [DeckSlide], songs: SongLookup) -> [(slideId: String, frame: PreviewFrame)] {
        slides.flatMap { s in SlideRender.frames(for: s, songs: songs).map { (s.id, $0) } }
    }
}

/// The slide list a TV shows for a Kids or Signage playlist (labels as in `Slide.label()` in the TV app's Model.kt).
public enum PlaylistOutline {
    public static func labels(for items: [PlaylistItem], songs: SongLookup) -> [String] {
        var out: [String] = []
        func blankOr(_ s: String?, _ d: String) -> String { (s?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? s! : d }
        for item in items {
            switch item.content {
            case .video: out.append("Video")
            case .image: out.append("Picture")
            case .countdown(let c): out.append(blankOr(c.countdown.title, "Countdown"))
            case .youtube: out.append("YouTube")
            case .sign(let s): out.append(blankOr(s.title, "Sign"))
            case .stream: out.append("Live stream")
            case .unknown: break
            case .lyrics(let l):
                var words: [String] = []
                var title = l.title
                if let id = l.songId {
                    guard let song = songs[id.lowercased()] else { continue }
                    title = song.title
                    words = SongExpander.expand(song).map(\.text)
                } else { words = l.slides }
                if l.showTitle == true { out.append("\(title) (title)") }
                for i in 0..<words.count { out.append("\(title) · Part \(i + 1) of \(words.count)") }
            }
        }
        return out
    }
}
