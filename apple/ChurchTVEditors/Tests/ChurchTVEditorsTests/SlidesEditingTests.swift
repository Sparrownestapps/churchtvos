import XCTest
import ChurchTVCore
@testable import ChurchTVEditors

final class SlidesEditingTests: XCTestCase {
    private func deck(_ n: Int) -> [DeckSlide] {
        var list: [DeckSlide] = []
        for _ in 0..<n { DeckEditing.add(.text, to: &list, after: nil) }
        return list
    }
    private let songId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    // MARK: Slides

    func testNewSlideDefaultsMatchTheWebsite() {
        var list: [DeckSlide] = []
        for k in DeckSlide.Kind.allCases { DeckEditing.add(k, to: &list, after: nil) }
        XCTAssertEqual(list.count, DeckSlide.Kind.allCases.count)
        XCTAssertEqual(Set(list.map(\.id)).count, list.count, "ids are unique")
        guard case .countdown(let c) = list[3].content else { return XCTFail() }
        XCTAssertEqual(c.atZero, .hold)
        XCTAssertEqual(c.ifPassed, .zero)
        XCTAssertEqual(c.seconds, 300)
        guard case .blank(let b) = list[6].content else { return XCTFail() }
        XCTAssertEqual(b.color, "#000000")
        guard case .media(let m) = list[1].content else { return XCTFail() }
        XCTAssertEqual(m.fit, .contain)
        XCTAssertEqual(m.audio, true)
        guard case .stream(let s) = list[4].content else { return XCTFail() }
        XCTAssertEqual(s.fallback, .skip)
        XCTAssertEqual(s.audio, false)
    }

    func testAddInsertsAfterTheSelectedSlide() {
        var list = deck(3)
        let after = list[0].id
        let id = DeckEditing.add(.blank, to: &list, after: after)
        XCTAssertEqual(list.map(\.id).firstIndex(of: id), 1)
        let end = DeckEditing.add(.blank, to: &list, after: nil)
        XCTAssertEqual(list.last?.id, end)
    }

    func testReorderDuplicateDelete() {
        var list = deck(4)
        let ids = list.map(\.id)
        DeckEditing.move(0, by: 1, in: &list)
        XCTAssertEqual(list.map(\.id), [ids[1], ids[0], ids[2], ids[3]])
        DeckEditing.move(0, by: -1, in: &list)   // out of range: nothing happens
        XCTAssertEqual(list.map(\.id), [ids[1], ids[0], ids[2], ids[3]])
        DeckEditing.move(3, by: 1, in: &list)
        XCTAssertEqual(list.map(\.id), [ids[1], ids[0], ids[2], ids[3]])
        DeckEditing.move(id: ids[3], onto: ids[1], in: &list)
        XCTAssertEqual(list.map(\.id), [ids[3], ids[1], ids[0], ids[2]])

        let copyId = DeckEditing.duplicate(1, in: &list)
        XCTAssertEqual(list.count, 5)
        XCTAssertEqual(list[2].id, copyId)
        XCTAssertNotEqual(list[1].id, list[2].id)
        XCTAssertEqual(list[1].content, list[2].content)

        // deleting selects the neighbour (the next, or the last one)
        let next = DeckEditing.remove(1, from: &list)
        XCTAssertEqual(next, list[1].id)
        XCTAssertEqual(DeckEditing.remove(3, from: &list), list.last?.id)
        var one = deck(1)
        XCTAssertNil(DeckEditing.remove(0, from: &one))
    }

    func testUnknownSlideSurvivesReorderAndDelete() throws {
        let raw = try RawJSON.parse(##"{"id":"s_new","kind":"hologram","depth":3,"notes":"keep"}"##).objectValue!
        var list = deck(2)
        list.append(DeckSlide(object: raw))
        DeckEditing.move(2, by: -2, in: &list)
        XCTAssertEqual(list[0].id, "s_new")
        XCTAssertNil(list[0].kind)
        XCTAssertEqual(list[0].object["depth"], .number(3))
        XCTAssertEqual(list[0].object["kind"], .string("hologram"))
        XCTAssertFalse(DeckEditing.supportsBackground(list[0]))
        XCTAssertEqual(DeckEditing.label(list[0], songs: [:], mediaTitle: { _ in nil }), "Unknown (hologram)")
        _ = DeckEditing.remove(0, from: &list)
        XCTAssertEqual(list.count, 2)
    }

    func testLabels() {
        var t = DeckSlide.new(.text, existing: [])
        t.content = .text(TextSlideContent(title: "Welcome\n  home ", body: "x"))
        XCTAssertEqual(DeckEditing.label(t, songs: [:], mediaTitle: { _ in nil }), "Welcome / home")
        t.content = .text(TextSlideContent(title: "", body: ""))
        XCTAssertEqual(DeckEditing.label(t, songs: [:], mediaTitle: { _ in nil }), "Empty text slide")
        var m = DeckSlide.new(.media, existing: [])
        XCTAssertEqual(DeckEditing.label(m, songs: [:], mediaTitle: { _ in nil }), "Choose a file")
        m.content = .media(MediaSlideContent(mediaId: "abc", url: "u", mediaKind: .video))
        XCTAssertEqual(DeckEditing.label(m, songs: [:], mediaTitle: { _ in nil }), "Video")
        XCTAssertEqual(DeckEditing.label(m, songs: [:], mediaTitle: { $0 == "abc" ? "Loop.mp4" : nil }), "Loop.mp4")
        let s = DeckSlide(id: "s_1", content: .song(SongSlideContent(songId: songId.uuidString.lowercased())))
        XCTAssertEqual(DeckEditing.label(s, songs: [:], mediaTitle: { _ in nil }), "Song removed")
    }

    // MARK: Draft validation and saving rules

    func testDeckDraftValidationAndSaveRule() {
        let org = UUID()
        var d = DeckDraft(organizationId: org, name: "")
        XCTAssertEqual(d.problem, "Give the deck a name.")
        let original = d
        d.name = "Sunday"
        XCTAssertNil(d.problem)
        XCTAssertTrue(DeckEditing.canSave(draft: d, original: original))
        DeckEditing.add(.media, to: &d.slides, after: nil)
        XCTAssertEqual(d.problem, "Slide 1: needs an image or video chosen.")
        XCTAssertFalse(DeckEditing.canSave(draft: d, original: original))
        // an existing, unchanged, valid deck cannot be saved (nothing changed)
        var saved = DeckDraft(isNew: false, organizationId: org, name: "Sunday")
        XCTAssertFalse(DeckEditing.canSave(draft: saved, original: saved))
        let before = saved
        saved.loops = true
        XCTAssertTrue(DeckEditing.canSave(draft: saved, original: before))
    }

    func testCleanedTrimsAndDropsEmptyNotes() {
        var d = DeckDraft(organizationId: UUID(), name: "  Hello  ")
        var s = DeckSlide.new(.text, existing: [])
        s.content = .text(TextSlideContent(title: "  Hi ", body: " there "))
        s.notes = "   "
        d.slides = [s]
        let c = d.cleaned()
        XCTAssertEqual(c.name, "Hello")
        XCTAssertNil(c.slides[0].notes)
        guard case .text(let t) = c.slides[0].content else { return XCTFail() }
        XCTAssertEqual(t.title, "Hi")
        XCTAssertEqual(t.body, "there")
    }

    // MARK: Backgrounds

    func testBackgroundSwitchingMatchesTheWebsite() {
        XCTAssertNil(BackgroundEditing.switched(.solid("#112233"), to: .inherit))
        let color = BackgroundEditing.switched(nil, to: .color)
        XCTAssertEqual(color?.color, SlideMetrics.defaultNavy)
        let withDim = SlideBackground.solid("#aa0000", dim: 0.4)
        let grad = BackgroundEditing.switched(withDim, to: .gradient)
        XCTAssertEqual(grad?.kind, .gradient)
        XCTAssertEqual(grad?.color, "#aa0000")
        XCTAssertEqual(grad?.color2, "#000000")
        XCTAssertEqual(grad?.angle, 135)
        XCTAssertEqual(grad?.dim, 0.4)
        let video = BackgroundEditing.switched(grad, to: .video)
        XCTAssertEqual(video?.kind, .video)
        XCTAssertEqual(video?.url, "")
        XCTAssertEqual(video?.fit, .cover)
        XCTAssertEqual(video?.dim, 0.4)
        XCTAssertFalse(video?.isUsable ?? true, "no file chosen yet")
        // same type again changes nothing
        XCTAssertEqual(BackgroundEditing.switched(video, to: .video), video)
        // a zero dim is not carried over
        XCTAssertNil(BackgroundEditing.switched(.solid("#fff000", dim: 0), to: .image)?.dim)
        XCTAssertEqual(BackgroundEditing.dimValue(percent: 0), nil)
        XCTAssertEqual(BackgroundEditing.dimValue(percent: 35), 0.35)
        XCTAssertEqual(BackgroundEditing.dimValue(percent: 99), 0.8)
    }

    func testBackgroundResolutionOrderAndEmptyFiles() {
        let slide = SlideBackground(kind: .image, mediaId: "", url: "")        // nothing chosen: skipped
        let deck = SlideBackground.solid("#222222")
        let theme = SlideBackground.solid("#333333")
        XCTAssertEqual(BackgroundResolver.resolve(slide: slide, deck: deck, theme: theme).color, "#222222")
        XCTAssertEqual(BackgroundResolver.resolve(slide: .solid("#111111"), deck: deck, theme: theme).color, "#111111")
        XCTAssertEqual(BackgroundResolver.resolve(slide: nil, deck: nil, theme: theme).color, "#333333")
        XCTAssertEqual(BackgroundResolver.resolve(slide: nil, deck: nil, theme: nil).color, SlideMetrics.defaultNavy)
        var d = DeckDraft(organizationId: UUID(), name: "x", background: SlideBackground(kind: .video, mediaId: "", url: ""))
        XCTAssertNotNil(d.problem)
        d.background = nil
        XCTAssertNil(d.problem)
    }

    func testBackgroundModeAndSummary() {
        XCTAssertEqual(BackgroundMode(nil), .inherit)
        XCTAssertEqual(BackgroundMode(.solid("#000000")), .color)
        XCTAssertEqual(BackgroundMode(SlideBackground(kind: .unknown("shader"))), .unknown("shader"))
        XCTAssertEqual(BackgroundEditing.summary(nil, inherit: "Using the theme background"), "Using the theme background")
        XCTAssertEqual(BackgroundEditing.summary(SlideBackground(kind: .video, url: ""), inherit: ""), "Video (none chosen)")
        XCTAssertEqual(BackgroundEditing.summary(SlideBackground(kind: .image, url: "u"), inherit: ""), "Image")
        // unknown backgrounds survive a trip through the model
        let raw = try! RawJSON.parse(##"{"type":"shader","speed":2,"dim":0.2}"##).objectValue!
        let bg = SlideBackground(object: raw)
        XCTAssertEqual(bg.object["speed"], .number(2))
        XCTAssertEqual(bg.object["type"], .string("shader"))
    }

    func testOversizeVideoWarning() {
        XCTAssertFalse(MediaSize.isOversize(kind: .video, bytes: 100 * 1024 * 1024))
        XCTAssertTrue(MediaSize.isOversize(kind: .video, bytes: 201 * 1024 * 1024))
        XCTAssertFalse(MediaSize.isOversize(kind: .image, bytes: 900 * 1024 * 1024))
        XCTAssertFalse(MediaSize.isOversize(kind: .video, bytes: nil))
    }

    // MARK: Songs and streams

    func testSongScreenCounts() {
        let song = Song(id: songId, title: "Test", sections: [SongSection(id: "v1", label: "Verse 1", text: "a\nb\nc\nd"), SongSection(id: "c", label: "Chorus", text: "x\ny")],
                        arrangement: ["v1", "c", "v1"], linesPerSlide: 2)
        let lookup = Song.lookup([song])
        // verse 1 = 2 slides, chorus = 1 slide, verse 1 again = 2 slides
        XCTAssertEqual(DeckEditing.songScreens(SongSlideContent(songId: songId.uuidString.lowercased(), showTitle: false), songs: lookup), 5)
        XCTAssertEqual(DeckEditing.songScreens(SongSlideContent(songId: songId.uuidString.uppercased(), showTitle: true), songs: lookup), 6)
        XCTAssertNil(DeckEditing.songScreens(SongSlideContent(songId: "missing"), songs: lookup))
        let slide = DeckSlide(id: "s_1", content: .song(SongSlideContent(songId: songId.uuidString.lowercased(), showTitle: true)))
        XCTAssertEqual(SlideRender.frames(for: slide, songs: lookup).count, 6)
    }

    func testStreamLinkChecks() {
        XCTAssertFalse(DeckEditing.canTestStream("rtmp://x"))
        XCTAssertFalse(DeckEditing.canTestStream("https://"))
        XCTAssertTrue(DeckEditing.canTestStream("https://example.com/a.m3u8"))
        XCTAssertTrue(DeckEditing.streamTestResult(status: 200, body: "#EXTM3U\n#EXT-X").ok)
        XCTAssertFalse(DeckEditing.streamTestResult(status: 200, body: "<html>").ok)
        XCTAssertTrue(DeckEditing.streamTestResult(status: 404, body: "").text.contains("404"))
        var slide = DeckSlide.new(.stream, existing: [])
        XCTAssertNotNil(slide.problem)
        slide.content = .stream(StreamSlideContent(title: "Live", url: "https://example.com/a.m3u8"))
        XCTAssertNil(slide.problem)
        XCTAssertEqual(DeckEditing.clampSeconds(0), 1)
        XCTAssertEqual(DeckEditing.clampSeconds(99999), 3600)
    }

    // MARK: Themes

    func testThemePresetsAreTheWebsitePresets() {
        XCTAssertEqual(ThemePreset.all.map(\.name), ["Classic dark blue", "Warm light", "Video-ready"])
        XCTAssertEqual(ThemePreset.all[2].config.background?.dim, 0.4)
        XCTAssertEqual(ThemePreset.all[1].config.textColor, "#2B2118")
    }

    func testContrastWarning() {
        var c = ThemeEditing.filled(ThemePreset.all[0].config)   // white on deep blue
        XCTAssertNil(ThemeEditing.contrastWarning(c))
        c.textColor = "#1f3a5f"                                    // same as the background
        XCTAssertNotNil(ThemeEditing.contrastWarning(c))
        XCTAssertTrue(ThemeEditing.contrastWarning(c)!.hasPrefix("Low contrast"))
        c.background = .gradient("#ffffff", "#000000")             // text "#1f3a5f" fails on one end
        XCTAssertNotNil(ThemeEditing.contrastWarning(c))
        c.background = .video(mediaId: "m", url: "u")              // pictures cannot be checked
        XCTAssertNil(ThemeEditing.contrastRatio(c))
        XCTAssertNil(ThemeEditing.contrastWarning(c))
        // a dim rescues light text on a light colour
        var light = ThemeEditing.filled(ThemeConfig(textColor: "#ffffff", background: .solid("#cccccc")))
        XCTAssertNotNil(ThemeEditing.contrastWarning(light))
        light.background = .solid("#cccccc", dim: 0.8)
        XCTAssertNil(ThemeEditing.contrastWarning(light))
    }

    func testFilledKeepsUnknownKeys() throws {
        let raw = try RawJSON.parse(##"{"font":"julius","text_color":"#ffffff","title_size":1.2,"future":{"a":[1,2]},"logo":{"show":true,"position":"top_left","tint":"red"},"background":{"type":"color","color":"#101010","grain":3}}"##).objectValue!
        let cfg = ThemeConfig(object: raw)
        let filled = ThemeEditing.filled(cfg)
        XCTAssertEqual(filled.titleScale, 1)
        XCTAssertEqual(filled.margin, 8)
        XCTAssertEqual(filled.font, .julius)
        let out = filled.object
        XCTAssertEqual(out["future"], raw["future"])
        XCTAssertEqual(out["title_size"], .number(1.2))
        XCTAssertEqual(out["logo"]?["tint"], .string("red"))
        XCTAssertEqual(out["logo"]?["position"], .string("top_left"))
        XCTAssertEqual(out["background"]?["grain"], .number(3))
        // applying a preset replaces the settings but keeps the unknown keys
        let applied = ThemeEditing.applying(ThemePreset.all[1], to: filled).object
        XCTAssertEqual(applied["text_color"], .string("#2B2118"))
        XCTAssertEqual(applied["future"], raw["future"])
        XCTAssertEqual(applied["logo"]?["tint"], .string("red"))
        XCTAssertEqual(applied["font"], .string("lato"))
    }

    func testThemeNameRules() {
        let org = UUID()
        let a = SlideTheme(organizationId: org, name: "Warm")
        let b = SlideTheme(organizationId: org, name: "Other")
        XCTAssertEqual(ThemeEditing.nameProblem(" ", others: [a, b], editing: a.id), "Give the theme a name.")
        XCTAssertEqual(ThemeEditing.nameProblem("warm", others: [a, b], editing: b.id), "A theme with that name already exists. Choose another name.")
        XCTAssertNil(ThemeEditing.nameProblem("Warm", others: [a, b], editing: a.id), "its own name is fine")
        var cfg = ThemeConfig.standard
        cfg.background = SlideBackground(kind: .image, url: "")
        XCTAssertNotNil(ThemeEditing.problem(name: "X", config: cfg, others: [], editing: a.id))
    }

    // MARK: Services (demo mode)

    @MainActor
    func testThemeSaveMapsDuplicateNameFromTheService() async throws {
        let model = TestHost()
        await model.start()
        await model.content.load(.slides)
        let themes = model.content.themes
        XCTAssertGreaterThanOrEqual(themes.count, 2)
        var t = themes[0]
        t.name = themes[1].name.uppercased()
        do { _ = try await model.content.save(t); XCTFail("should be refused") }
        catch { XCTAssertEqual(Formatting.message(for: error), "A theme with that name already exists. Choose another name.") }
        t.name = "Fresh look"
        t.config.shadow = false
        let saved = try await model.content.save(t)
        XCTAssertEqual(saved.name, "Fresh look")
        XCTAssertEqual(model.content.themes.first { $0.id == t.id }?.config.shadow, false)
    }

    @MainActor
    func testDeckSaveRoundTripInDemoMode() async throws {
        let model = TestHost()
        await model.start()
        await model.content.load(.slides)
        await model.content.loadSupport()
        var draft = model.content.newDeckDraft(name: "  Phone deck ")
        DeckEditing.add(.text, to: &draft.slides, after: nil)
        draft.slides[0].content = .text(TextSlideContent(title: "Hi", body: ""))
        draft.background = .gradient("#000000", "#1f3a5f", angle: 90, dim: 0.2)
        let saved = try await model.content.save(draft.cleaned())
        XCTAssertEqual(saved.name, "Phone deck")
        XCTAssertEqual(saved.background?.angle, 90)
        XCTAssertEqual(DeckDraft(saved).slides.count, 1)
        // an invalid deck is refused with the website's text
        var bad = DeckDraft(saved)
        DeckEditing.add(.song, to: &bad.slides, after: nil)
        do { _ = try await model.content.save(bad); XCTFail("should be refused") }
        catch { XCTAssertEqual(Formatting.message(for: error), "Slide 2: needs a song chosen.") }
    }
}
