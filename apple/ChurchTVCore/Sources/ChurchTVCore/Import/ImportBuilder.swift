import Foundation

/// Turns imported pages into deck slides or playlist items, and decides where they go. Same shapes as
/// deckSlidesFrom / playlistItemsFrom in dashboard/src/importer/importLogic.ts. Pure and unit tested.
public enum ImportBuilder {
    /// Default time per page: decks are stepped through with the remote (wait for Next), Kids playlists move on by themselves.
    public static func defaultSeconds(forDeck: Bool) -> Int? { forDeck ? nil : 10 }

    /// Choices for "How long does each page show", in menu order. nil = wait for Next.
    public static let durationChoices: [Int?] = [nil, 5, 10, 15, 30, 60]

    public static func durationLabel(_ seconds: Int?) -> String { seconds.map { "\($0) seconds" } ?? "Wait for Next" }

    // MARK: Decks

    /// One slide per page, in order. Ids are unique within `existing + result`. Pictures and videos are "contain" on black
    /// so the whole page shows; text slides carry no look of their own (the theme decides).
    public static func deckSlides(pages: [ImportedPage], seconds: Int?, existing: [DeckSlide]) -> [DeckSlide] {
        var all = existing
        var out: [DeckSlide] = []
        for page in pages {
            let id = DeckSlide.newId(existing: all)
            let notes = page.notes.trimmed.isEmpty ? nil : page.notes.trimmed
            var slide: DeckSlide?
            if let m = page.media {
                let isVideo = m.kind == .video
                var c = MediaSlideContent(fit: .contain, seconds: isVideo ? nil : seconds, audio: isVideo ? true : nil)
                c.apply(m)
                slide = DeckSlide(id: id, background: .solid("#000000"), notes: notes, content: .media(c))
            } else if let t = page.text {
                let title = t.title, body = t.body
                let layout: SlideLayout = !title.isEmpty && !body.isEmpty ? .titleBody : !title.isEmpty ? .title : .body
                slide = DeckSlide(id: id, notes: notes, content: .text(TextSlideContent(title: title, body: body, layout: layout, seconds: seconds)))
            }
            if let slide { out.append(slide); all.append(slide) }
        }
        return out
    }

    // MARK: Kids playlists

    /// One item per page: pictures (also drawn text slides) and videos. Speaker notes are not kept (Kids items have no notes).
    public static func playlistItems(pages: [ImportedPage], seconds: Int?) -> [PlaylistItem] {
        pages.compactMap { page in
            guard let m = page.media else { return nil }
            if m.kind == .video {
                var clip = MediaClip(writesSeconds: false)
                clip.apply(m)
                return PlaylistItem(.video(clip))
            }
            var clip = MediaClip(seconds: seconds)
            clip.apply(m)
            return PlaylistItem(.image(clip))
        }
    }

    // MARK: Placement

    /// Inserts `new` into `list` and returns the index of the first inserted element. `.after(n)` puts them after element n (0 = start).
    @discardableResult
    public static func insert<T>(_ new: [T], into list: inout [T], placement: ImportPlacement) -> Int {
        let index: Int
        switch placement {
        case .append, .newItem: index = list.count
        case .after(let n): index = min(max(n, 0), list.count)
        }
        list.insert(contentsOf: new, at: index)
        return index
    }

    // MARK: Entry helpers

    /// Why the import button is disabled, or nil when it can run.
    public static func problem(entries: [ImportEntry], placement: ImportPlacement) -> String? {
        let n = entries.filter(\.included).count
        if n == 0 { return "Tick at least one page to import." }
        if n > ImportLimits.maxPages { return "You ticked \(n) pages. Import at most \(ImportLimits.maxPages) at a time." }
        if case .newItem(let name) = placement, name.trimmed.isEmpty { return "Give the new item a name." }
        return nil
    }

    /// "12 pages" / "1 slide".
    public static func count(_ n: Int, _ kind: ImportKind) -> String { "\(n) \(kind.unit)\(n == 1 ? "" : "s")" }
}
