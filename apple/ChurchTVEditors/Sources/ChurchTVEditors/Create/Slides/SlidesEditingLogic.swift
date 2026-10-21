import Foundation
import ChurchTVCore

// Pure editing rules for the deck editor, background picker and theme editor (no UI, unit tested in SlidesEditingTests).
// They mirror dashboard/src/slides/DeckEditor.tsx, BackgroundPicker.tsx and ThemesPage.tsx.

/// The choices of the background picker. `inherit` means "no override": the level above shows through.
enum BackgroundMode: Hashable {
    case inherit, color, gradient, image, video
    case unknown(String)

    init(_ b: SlideBackground?) {
        guard let b else { self = .inherit; return }
        switch b.kind {
        case .color: self = .color
        case .gradient: self = .gradient
        case .image: self = .image
        case .video: self = .video
        case .unknown(let s): self = .unknown(s)
        }
    }

    static let choices: [BackgroundMode] = [.inherit, .color, .gradient, .image, .video]

    var label: String {
        switch self {
        case .inherit: return "Use default"
        case .color: return "Colour"
        case .gradient: return "Gradient"
        case .image: return "Image"
        case .video: return "Video"
        case .unknown(let s): return "Unknown type (\(s))"
        }
    }
}

enum BackgroundEditing {
    /// Switching the type (BackgroundPicker.tsx `switchTo`): the dim and a colour carry over; file backgrounds start empty.
    static func switched(_ value: SlideBackground?, to mode: BackgroundMode) -> SlideBackground? {
        if BackgroundMode(value) == mode { return value }
        let dim: Double? = (value?.dim ?? 0) > 0 ? value?.dim : nil
        let prev = value?.color
        switch mode {
        case .inherit, .unknown: return nil
        case .color:
            return SlideBackground(kind: .color, color: prev ?? SlideMetrics.defaultNavy, dim: dim)
        case .gradient:
            return SlideBackground(kind: .gradient, color: prev ?? SlideMetrics.defaultNavy,
                                   color2: value?.kind == .gradient ? (value?.color2 ?? "#000000") : "#000000", angle: 135, dim: dim)
        case .image:
            return SlideBackground(kind: .image, color: "#000000", mediaId: "", url: "", fit: .cover, dim: dim)
        case .video:
            return SlideBackground(kind: .video, color: "#000000", mediaId: "", url: "", fit: .cover, dim: dim)
        }
    }

    /// Dim slider percent (0...80) to the stored value (0 is stored as "no dim").
    static func dimValue(percent: Double) -> Double? {
        let p = min(80, max(0, percent))
        return p <= 0 ? nil : (p).rounded() / 100
    }

    /// Short text for rows ("Using the theme background", "Colour", "Video (none chosen)").
    static func summary(_ b: SlideBackground?, inherit: String) -> String {
        guard let b else { return inherit }
        switch b.kind {
        case .color: return "Colour"
        case .gradient: return "Gradient"
        case .image: return (b.url ?? "").isEmpty ? "Image (none chosen)" : "Image"
        case .video: return (b.url ?? "").isEmpty ? "Video (none chosen)" : "Video"
        case .unknown(let s): return "Unknown type (\(s))"
        }
    }

    static let videoGuidance = "Video backgrounds play muted and loop. Use 1080p H.264, with loops of 10 to 60 seconds, and keep the file modest: Fire TV sticks have little storage. Portrait screens crop a landscape video unless the fit is set to show it all."
    static let imageGuidance = "Use 1920 x 1080 for landscape screens. Portrait screens crop a landscape picture unless the fit shows it all."
}

enum MediaSize {
    /// OVERSIZE_VIDEO_BYTES in render.ts.
    static let oversizeBytes: Int64 = 200 * 1024 * 1024
    static func isOversize(kind: MediaKind, bytes: Int64?) -> Bool { kind == .video && (bytes ?? 0) > oversizeBytes }
    static let warning = "This video is over 200 MB. Fire TV sticks have little storage; a smaller file (1080p H.264) is safer."
}

enum DeckEditing {
    /// Inserts a new slide of `kind` after the slide with id `after` (at the end when nil or not found). Returns the new slide's id.
    @discardableResult
    static func add(_ kind: DeckSlide.Kind, to slides: inout [DeckSlide], after id: String?) -> String {
        let s = DeckSlide.new(kind, existing: slides)
        let at = id.flatMap { id in slides.firstIndex { $0.id == id }.map { $0 + 1 } } ?? slides.count
        slides.insert(s, at: at)
        return s.id
    }

    /// Copies the slide at `index` right after it, with a new id. Returns the copy's id.
    @discardableResult
    static func duplicate(_ index: Int, in slides: inout [DeckSlide]) -> String? {
        guard slides.indices.contains(index) else { return nil }
        let copy = slides[index].duplicated(existing: slides)
        slides.insert(copy, at: index + 1)
        return copy.id
    }

    /// Removes the slide at `index` and returns the id of the slide to select next (the neighbour), or nil when the deck is empty.
    static func remove(_ index: Int, from slides: inout [DeckSlide]) -> String? {
        guard slides.indices.contains(index) else { return slides.first?.id }
        slides.remove(at: index)
        return slides.isEmpty ? nil : slides[min(index, slides.count - 1)].id
    }

    /// Moves the slide at `index` by `by` places (clamped like `moveItem` in lib.ts: out of range does nothing).
    static func move(_ index: Int, by: Int, in slides: inout [DeckSlide]) {
        let to = index + by
        guard slides.indices.contains(index), slides.indices.contains(to), by != 0 else { return }
        let s = slides.remove(at: index)
        slides.insert(s, at: to)
    }

    /// Moves the slide with id `id` so that it sits where the slide `target` is now (drag and drop onto a thumbnail).
    static func move(id: String, onto target: String, in slides: inout [DeckSlide]) {
        guard id != target, let from = slides.firstIndex(where: { $0.id == id }), let to = slides.firstIndex(where: { $0.id == target }) else { return }
        move(from, by: to - from, in: &slides)
    }

    /// One line describing a slide for the strip (slideLabel in render.ts).
    static func label(_ slide: DeckSlide, songs: SongLookup, mediaTitle: (String) -> String?) -> String {
        func oneLine(_ s: String?) -> String {
            (s ?? "").split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " / ")
        }
        switch slide.content {
        case .text(let t):
            let a = oneLine(t.title), b = oneLine(t.body)
            return !a.isEmpty ? a : !b.isEmpty ? b : "Empty text slide"
        case .media(let m):
            if let title = mediaTitle(m.mediaId), !title.isEmpty { return title }
            return m.mediaId.isEmpty ? "Choose a file" : (m.mediaKind == .video ? "Video" : "Image")
        case .song(let s):
            if let song = songs[s.songId.lowercased()] { return song.title }
            return s.songId.isEmpty ? "Choose a song" : "Song removed"
        case .countdown(let c):
            let t = oneLine(c.title)
            return t.isEmpty ? "Countdown" : t
        case .stream(let s):
            let t = oneLine(s.title)
            return t.isEmpty ? "Live stream" : t
        case .blank: return "Blank"
        case .unknown(let k): return k.isEmpty ? "Unknown slide" : "Unknown (\(k))"
        }
    }

    /// "Makes N screens on the TV" (songScreenCount in render.ts), nil when the song is not chosen or missing.
    static func songScreens(_ s: SongSlideContent, songs: SongLookup) -> Int? {
        guard let song = songs[s.songId.lowercased()] else { return nil }
        return SlideRender.songScreenCount(showTitle: s.showTitle == true, song: song)
    }

    /// Slides that cannot have a background override in the website's editor (blank and stream draw their own screen).
    static func supportsBackground(_ slide: DeckSlide) -> Bool {
        switch slide.content {
        case .blank, .stream, .unknown: return false
        default: return true
        }
    }

    /// The Save button rule: valid and (changed or never saved).
    static func canSave(draft: DeckDraft, original: DeckDraft) -> Bool {
        draft.problem == nil && (draft != original || draft.isNew)
    }

    /// Seconds for "Automatically after...": default 10, kept within 1...3600.
    static func clampSeconds(_ v: Int) -> Int { min(3600, max(1, v)) }

    /// Is this stream link acceptable for the Test link button?
    static func canTestStream(_ url: String) -> Bool { StreamItem.isValidURL(url) }

    /// What the Test link check says about an HLS playlist body (render of StreamEditor.test in SlideEditors.tsx).
    static func streamTestResult(status: Int, body: String) -> (ok: Bool, text: String) {
        if !(200..<300).contains(status) { return (false, "The server answered \(status). Check the link, and that the broadcast is live.") }
        return body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
            ? (true, "The link answered and looks like an HLS stream.")
            : (false, "The link answered, but it doesn't look like an .m3u8 stream playlist. Double-check you copied the M3U8 link.")
    }
}

enum ThemeEditing {
    /// Fills the blanks with the defaults so every control shows a real value (resolvedForEditing in ThemesPage.tsx), keeping the
    /// background and every key the app does not know (`extra`, `logo.extra`).
    static func filled(_ c: ThemeConfig) -> ThemeConfig {
        let r = c.resolved
        var out = c
        out.font = r.font; out.titleScale = r.titleScale; out.bodyScale = r.bodyScale; out.textColor = r.textColor
        out.align = r.align; out.position = r.position; out.shadow = r.shadow; out.outline = r.outline
        out.margin = r.margin; out.showLabels = r.showLabels
        out.logo = ThemeLogo(show: r.logo.show, position: r.logo.position, extra: c.logo?.extra ?? [:])
        return out
    }

    /// Applies a preset's settings to `config` but keeps unknown keys (the preset replaces everything the editor can edit).
    static func applying(_ preset: ThemePreset, to config: ThemeConfig) -> ThemeConfig {
        var out = filled(preset.config)
        out.extra = config.extra
        out.logo?.extra = config.logo?.extra ?? [:]
        return out
    }

    /// Contrast text for the warning, or nil when fine or when the background is a picture (cannot be checked).
    static func contrastRatio(_ config: ThemeConfig) -> Double? {
        let bg = BackgroundResolver.resolve(slide: nil, deck: nil, theme: config.background)
        return BackgroundResolver.worstContrast(textColor: config.resolved.textColor, bg: bg)
    }

    static func contrastWarning(_ config: ThemeConfig) -> String? {
        guard let ratio = contrastRatio(config), ratio < 4.5 else { return nil }
        return "Low contrast: this text colour on the background is \(String(format: "%.1f", ratio)):1. Aim for 4.5:1 or more so it reads from the back of the room. Try a lighter or darker text colour, or a darker dim."
    }

    /// Name check before saving (the server also enforces it). Returns text to show or nil.
    static func nameProblem(_ name: String, others: [SlideTheme], editing id: UUID) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "Give the theme a name." }
        if others.contains(where: { $0.id != id && $0.name.lowercased() == n.lowercased() }) { return "A theme with that name already exists. Choose another name." }
        return nil
    }

    /// The background must have its file when it is an image or video.
    static func backgroundProblem(_ config: ThemeConfig) -> String? {
        if let b = config.background, (b.kind == .image || b.kind == .video), !b.isUsable {
            return "The background needs an image or video chosen (or set it back to the default)."
        }
        return nil
    }

    static func problem(name: String, config: ThemeConfig, others: [SlideTheme], editing id: UUID) -> String? {
        nameProblem(name, others: others, editing: id) ?? backgroundProblem(config)
    }

    /// Sample slides for the preview (SAMPLES in ThemesPage.tsx).
    enum Sample: String, CaseIterable, Identifiable {
        case text, lyric, lower
        var id: String { rawValue }
        var label: String { switch self { case .text: return "Text slide"; case .lyric: return "Lyrics"; case .lower: return "Lower third" } }
        var frame: PreviewFrame {
            switch self {
            case .text: return .text(layout: .titleBody, title: "Welcome to church", body: "We're glad you're here. Service starts at 10:00.", align: nil, color: nil)
            case .lyric: return .lyric(text: "Amazing grace, how sweet the sound\nThat saved a wretch like me", label: "Verse 1", n: 1, count: 6)
            case .lower: return .text(layout: .lowerThird, title: "Pastor Keith", body: "Worship Pastor", align: nil, color: nil)
            }
        }
    }
}
