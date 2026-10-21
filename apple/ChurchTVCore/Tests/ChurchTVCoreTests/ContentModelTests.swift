import XCTest
@testable import ChurchTVCore

final class ContentModelTests: XCTestCase {
    // MARK: Helpers

    /// Decodes `json` as T, encodes it again and returns the result as comparable RawJSON.
    private func roundTrip<T: Codable>(_ type: T.Type, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> RawJSON {
        let value = try ContentJSON.decoder().decode(T.self, from: Data(json.utf8))
        let data = try ContentJSON.encoder().encode(value)
        return try JSONDecoder().decode(RawJSON.self, from: data)
    }

    /// The round trip must give back exactly the same JSON (nothing lost, nothing invented).
    private func assertStable<T: Codable>(_ type: T.Type, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let out = try roundTrip(type, json, file: file, line: line)
        XCTAssertEqual(out, try RawJSON.parse(json), "round trip changed \(json)", file: file, line: line)
    }

    // MARK: RawJSON

    func testRawJSONKeepsNumbersAndKeys() throws {
        let json = ##"{"a":1,"b":2.5,"c":[true,null,"x"],"snake_case_key":{"camelKey":0}}"##
        try assertStable(RawJSON.self, json)
        let text = String(data: try ContentJSON.encoder().encode(try RawJSON.parse(##"{"seconds":30}"##)), encoding: .utf8)
        XCTAssertEqual(text, ##"{"seconds":30}"##)
    }

    // MARK: Playlist items

    func testKidsItemsRoundTrip() throws {
        let shapes = [
            ##"{"type":"video","title":"Week 1","url":"https://x/y.mp4","media_id":"m1"}"##,
            ##"{"type":"image","title":"Verse","url":"https://x/y.jpg","media_id":"m2","seconds":null}"##,
            ##"{"type":"image","title":"Verse","url":"https://x/y.jpg","media_id":"m2","seconds":12}"##,
            ##"{"type":"countdown","title":"Service starts in","seconds":300}"##,
            ##"{"type":"countdown","title":"Start","mode":"until","until":"09:30","at_zero":"hold","if_passed":"skip"}"##,
            ##"{"type":"countdown","title":"Go","mode":"duration","seconds":120,"audio":{"media_id":"a1","url":"https://x/a.mp3","volume":0.5,"loop":false,"fade_seconds":4,"align_end":true},"at_zero":"next","if_passed":"zero"}"##,
            ##"{"type":"lyrics","title":"Song","slides":["Verse 1","Chorus"]}"##,
            ##"{"type":"lyrics","title":"Song","slides":["Verse 1"],"show_title":true}"##,
            ##"{"type":"lyrics","title":"Song","song_id":"11111111-1111-4111-8111-111111111111","show_title":false}"##,
            ##"{"type":"youtube","title":"Live","video_id":null,"channel_id":"UC123","start":null}"##,
            ##"{"type":"youtube","title":"Clip","video_id":"abcdefghijk","channel_id":null,"start":30}"##,
            ##"{"type":"stream","title":"Live","url":"https://x/a.m3u8","seconds":null,"audio":false,"fallback":"skip"}"##,
            ##"{"type":"stream","title":"Live","url":"https://x/a.m3u8","seconds":60,"audio":true,"fallback":"hold"}"##,
            ##"{"type":"sign","title":"Welcome","subtext":"Coffee","background":"#1f3a5f","seconds":10,"align":"left","logo":true}"##,
            ##"{"type":"video","title":"Loop","url":"u","seconds":null,"media_id":"m"}"##,
        ]
        for s in shapes { try assertStable(PlaylistItem.self, s) }
    }

    func testUnknownKeysAndTypesSurvive() throws {
        // an extra key on every known type
        let extras = [
            ##"{"type":"video","title":"V","url":"u","media_id":"m","caption":"hello","nested":{"x":[1,2,{"y":null}]}}"##,
            ##"{"type":"image","title":"I","url":"u","media_id":"m","seconds":5,"effect":"zoom"}"##,
            ##"{"type":"countdown","title":"C","seconds":10,"theme":"red","audio":{"media_id":"a","url":"u","pan":0.2}}"##,
            ##"{"type":"lyrics","title":"L","slides":["a"],"transition":"fade"}"##,
            ##"{"type":"lyrics","title":"L","song_id":"s","key":"G"}"##,
            ##"{"type":"youtube","title":"Y","video_id":null,"channel_id":"c","start":null,"quality":"hd"}"##,
            ##"{"type":"stream","title":"S","url":"https://x/a.m3u8","seconds":null,"audio":false,"fallback":"skip","latency":"low"}"##,
            ##"{"type":"sign","title":"S","subtext":"","background":"#000000","seconds":10,"align":"center","logo":false,"icon":"star"}"##,
            // an unknown item type is kept whole
            ##"{"type":"poll","question":"Favourite colour?","options":["red","blue"],"title":"Poll"}"##,
        ]
        for s in extras { try assertStable(PlaylistItem.self, s) }
        let unknown = try ContentJSON.decoder().decode(PlaylistItem.self, from: Data(##"{"type":"poll","title":"P"}"##.utf8))
        guard case .unknown(let u) = unknown.content else { return XCTFail("expected unknown") }
        XCTAssertEqual(u.typeName, "poll")
        XCTAssertNil(unknown.typeName)
        XCTAssertNil(unknown.problem)
    }

    func testEditingKeepsUnknownKeys() throws {
        var item = try ContentJSON.decoder().decode(PlaylistItem.self, from: Data(##"{"type":"image","title":"I","url":"u","media_id":"m","seconds":5,"effect":"zoom"}"##.utf8))
        guard case .image(var clip) = item.content else { return XCTFail() }
        clip.seconds = 20; clip.title = "New"
        item.content = .image(clip)
        let out = try JSONDecoder().decode(RawJSON.self, from: ContentJSON.encoder().encode(item))
        XCTAssertEqual(out["effect"], .string("zoom"))
        XCTAssertEqual(out["seconds"], .number(20))
        XCTAssertEqual(out["title"], .string("New"))
        // clearing the seconds of an image writes null (wait for Next)
        clip.seconds = nil
        item.content = .image(clip)
        let cleared = try JSONDecoder().decode(RawJSON.self, from: ContentJSON.encoder().encode(item))
        XCTAssertEqual(cleared["seconds"], .null)
    }

    func testCountdownFields() throws {
        // Old Kids item: only title and seconds. It must not grow new keys.
        let old = try ContentJSON.decoder().decode(PlaylistItem.self, from: Data(##"{"type":"countdown","title":"Service starts in","seconds":300}"##.utf8))
        guard case .countdown(let c) = old.content else { return XCTFail() }
        XCTAssertEqual(c.countdown.effectiveAtZero, .next, "a missing at_zero means 'next' (old behaviour)")
        XCTAssertEqual(c.countdown.effectiveMode, .duration)
        XCTAssertEqual(c.countdown.effectiveIfPassed, .zero)
        XCTAssertNil(c.countdown.problem)
        try assertStable(PlaylistItem.self, ##"{"type":"countdown","title":"Service starts in","seconds":300}"##)

        // New countdowns are saved with hold / zero.
        let new = CountdownSettings.new
        XCTAssertEqual(new.atZero, .hold); XCTAssertEqual(new.ifPassed, .zero); XCTAssertEqual(new.mode, .duration); XCTAssertEqual(new.seconds, 300)
        let obj = PlaylistItem.newCountdown().object
        XCTAssertEqual(obj["at_zero"], .string("hold"))
        XCTAssertEqual(obj["mode"], .string("duration"))

        // until mode
        var s = CountdownSettings(title: "x", mode: .duration, seconds: 0)
        XCTAssertEqual(s.problem, "the countdown needs at least 1 second.")
        s.setMode(.until)
        XCTAssertEqual(s.until, "09:00"); XCTAssertNil(s.problem)
        s.until = "25:00"; XCTAssertNotNil(s.problem)
        s.until = "9:00"; XCTAssertNotNil(s.problem)
        s.setMode(.duration)
        XCTAssertEqual(s.seconds, 300)
        s.audio = CountdownAudio(mediaId: "a", url: "")
        XCTAssertEqual(s.problem, "choose an audio file, or remove the audio.")
        s.setAudio(mediaId: "b", url: "https://x/b.mp3")
        XCTAssertNil(s.problem)
        XCTAssertEqual(s.audio?.effectiveVolume, 0.8); XCTAssertEqual(s.audio?.effectiveFadeSeconds, 3)
        XCTAssertEqual(s.audio?.effectiveLoop, true); XCTAssertEqual(s.audio?.effectiveAlignEnd, false)
    }

    func testPlaylistItemChecks() {
        XCTAssertNotNil(PlaylistItem.newVideo().problem)
        XCTAssertNotNil(PlaylistItem.newStream().problem)
        XCTAssertNotNil(PlaylistItem.newSign().problem)
        XCTAssertNotNil(PlaylistItem.newYouTube(channelId: nil).problem)
        XCTAssertNil(PlaylistItem.newYouTube(channelId: "UC1").problem)
        XCTAssertNil(PlaylistItem.newLyrics().problem)           // typed lyrics start empty and are allowed
        XCTAssertTrue(StreamItem.isValidURL("https://example.com/a.m3u8"))
        XCTAssertFalse(StreamItem.isValidURL("ftp://example.com"))
        XCTAssertFalse(StreamItem.isValidURL("https://"))
        // Signage images default to 10 s, Kids images wait
        XCTAssertEqual(PlaylistItem.new(.image, kind: .signage).object["seconds"], .number(10))
        XCTAssertEqual(PlaylistItem.new(.image, kind: .kids).object["seconds"], .null)
        XCTAssertNil(PlaylistItem.new(.video, kind: .kids).object["seconds"])
        XCTAssertEqual(PlaylistItem.new(.video, kind: .signage).object["seconds"], .null)
        XCTAssertTrue(PlaylistKind.signage.supports(.sign)); XCTAssertFalse(PlaylistKind.kids.supports(.sign))
    }

    // MARK: Slides, backgrounds, themes

    func testDeckSlidesRoundTrip() throws {
        let slides = [
            ##"{"id":"s_a","kind":"text","title":"Welcome","body":"Hi","layout":"title_body","seconds":null}"##,
            ##"{"id":"s_a","kind":"text","title":"Hi","body":"","layout":"lower_third","align":"left","text_color":"#ff0000","seconds":8,"notes":"private"}"##,
            ##"{"id":"s_b","kind":"media","media_id":"m","url":"u","media_kind":"video","fit":"cover","seconds":null,"audio":false}"##,
            ##"{"id":"s_b","kind":"media","media_id":"m","url":"u","media_kind":"image","fit":"contain","seconds":6,"audio":true}"##,
            ##"{"id":"s_c","kind":"song","song_id":"11111111-1111-4111-8111-111111111111","show_title":true}"##,
            ##"{"id":"s_d","kind":"countdown","title":"Starts in","mode":"until","until":"10:30","at_zero":"hold","if_passed":"skip"}"##,
            ##"{"id":"s_d","kind":"countdown","title":"Starts in","mode":"duration","seconds":300,"audio":{"media_id":"a","url":"u","volume":0.8,"loop":true,"fade_seconds":3,"align_end":false},"at_zero":"hold","if_passed":"zero"}"##,
            ##"{"id":"s_e","kind":"stream","title":"Live","url":"https://x/a.m3u8","audio":false,"fallback":"skip","seconds":null}"##,
            ##"{"id":"s_f","kind":"blank","color":"#000000"}"##,
            ##"{"id":"s_g","kind":"blank"}"##,
            // overrides and unknown fields on a slide
            ##"{"id":"s_h","kind":"blank","color":"#000000","background":{"type":"gradient","color":"#111111","color2":"#222222","angle":90,"dim":0.2},"future":{"a":1}}"##,
            // a kind this app does not know
            ##"{"id":"s_i","kind":"poll","question":"?","background":{"type":"color","color":"#123456"}}"##,
        ]
        for s in slides { try assertStable(DeckSlide.self, s) }
        let unknown = try ContentJSON.decoder().decode(DeckSlide.self, from: Data(slides.last!.utf8))
        XCTAssertNil(unknown.kind)
        guard case .unknown(let k) = unknown.content else { return XCTFail() }
        XCTAssertEqual(k, "poll")
        XCTAssertEqual(unknown.background?.color, "#123456")
    }

    func testBackgroundsRoundTrip() throws {
        let shapes = [
            ##"{"type":"color","color":"#1f3a5f"}"##,
            ##"{"type":"color","color":"#1f3a5f","dim":0.4}"##,
            ##"{"type":"gradient","color":"#000000","color2":"#ffffff","angle":135,"dim":0.1}"##,
            ##"{"type":"gradient","color":"#000000","color2":"#ffffff"}"##,
            ##"{"type":"image","media_id":"m","url":"https://x/a.jpg","fit":"contain","color":"#000000","dim":0.3}"##,
            ##"{"type":"video","media_id":"m","url":"https://x/a.mp4","fit":"cover","dim":0.5}"##,
            ##"{"type":"hologram","depth":3}"##,
        ]
        for s in shapes { try assertStable(SlideBackground.self, s) }
        let img = try ContentJSON.decoder().decode(SlideBackground.self, from: Data(shapes[4].utf8))
        XCTAssertEqual(img.kind, .image); XCTAssertEqual(img.fit, .contain); XCTAssertEqual(img.dim, 0.3); XCTAssertTrue(img.isUsable)
        XCTAssertFalse(SlideBackground.image(mediaId: "", url: "").isUsable)
        XCTAssertFalse(try ContentJSON.decoder().decode(SlideBackground.self, from: Data(shapes[6].utf8)).isUsable)
    }

    func testThemeConfigRoundTrip() throws {
        let full = ##"{"font":"julius","title_scale":1.2,"body_scale":0.9,"text_color":"#FFFFFF","align":"left","position":"lower","shadow":true,"outline":true,"margin":10,"background":{"type":"color","color":"#1f3a5f","dim":0.2},"show_labels":false,"logo":{"show":true,"position":"top_right"}}"##
        try assertStable(ThemeConfig.self, full)
        try assertStable(ThemeConfig.self, ##"{}"##)
        // an older theme with title_size, a future key and an unknown key inside logo
        try assertStable(ThemeConfig.self, ##"{"title_size":1,"future":[1,2],"logo":{"show":false,"position":"bottom_left","opacity":0.5}}"##)
        for p in ThemePreset.all { _ = try roundTrip(ThemeConfig.self, String(data: ContentJSON.encoder().encode(p.config), encoding: .utf8)!) }
        // defaults
        let r = ThemeConfig().resolved
        XCTAssertEqual(r.textColor, "#FFFFFF"); XCTAssertEqual(r.margin, 8); XCTAssertEqual(r.position, .center); XCTAssertTrue(r.shadow); XCTAssertTrue(r.showLabels)
        XCTAssertEqual(ThemeConfig(titleScale: 9, margin: 99).resolved.titleScale, 1.5)
        XCTAssertEqual(ThemeConfig(titleScale: 9, margin: 99).resolved.margin, 20)
    }

    func testRowsDecodeAndKeepJSON() throws {
        let org = UUID().uuidString.lowercased()
        let row = ##"{"id":"11111111-1111-4111-8111-111111111111","organization_id":"\##(org)","site_id":null,"name":"Week 3","created_at":"2026-10-21T10:00:00.123456+00:00","updated_at":"2026-10-21T11:00:00Z","items":[{"type":"video","title":"V","url":"u","media_id":"m","x":1},{"type":"poll","title":"?"}]}"##
        let p = try ContentJSON.decoder().decode(Playlist.self, from: Data(row.utf8))
        XCTAssertEqual(p.name, "Week 3"); XCTAssertNil(p.siteId); XCTAssertEqual(p.itemCount, 2); XCTAssertNotNil(p.updatedAt)
        let draft = PlaylistDraft(p)
        let body = try JSONDecoder().decode(RawJSON.self, from: ContentJSON.encoder().encode(draft.write(includeId: false)))
        XCTAssertEqual(body["site_id"], .null, "site_id is always sent, null = all sites")
        XCTAssertEqual(body["organization_id"]?.stringValue?.lowercased(), org)
        XCTAssertNil(body["id"])
        XCTAssertEqual(body["items"]?.arrayValue?.count, 2)
        XCTAssertEqual(body["items"]?.arrayValue?[0]["x"], .number(1))

        let deckRow = ##"{"id":"22222222-2222-4222-8222-222222222222","organization_id":"\##(org)","site_id":null,"name":"Sunday","theme_id":null,"background":{"type":"color","color":"#000000"},"loops":true,"created_at":"2026-10-21T10:00:00Z","updated_at":"2026-10-21T10:00:00Z","slides":[{"id":"s_1","kind":"blank","color":"#000000"},{"id":"s_2","kind":"future","a":1}]}"##
        let d = try ContentJSON.decoder().decode(SlideDeck.self, from: Data(deckRow.utf8))
        XCTAssertTrue(d.loops); XCTAssertEqual(d.slideCount, 2); XCTAssertEqual(d.background?.color, "#000000")
        let dbody = try JSONDecoder().decode(RawJSON.self, from: ContentJSON.encoder().encode(DeckDraft(d).write(includeId: true)))
        XCTAssertEqual(dbody["theme_id"], .null)
        XCTAssertEqual(dbody["slides"]?.arrayValue?[1]["a"], .number(1))
    }

    func testDraftChecks() {
        let org = UUID()
        var d = PlaylistDraft(organizationId: org, name: " ")
        XCTAssertEqual(d.problem(kind: .kids), "Give the playlist a name.")
        d.name = "Week 1"; d.items = [PlaylistItem.newVideo()]
        XCTAssertEqual(d.problem(kind: .kids), "Item 1 needs a video chosen.")
        d.items = [PlaylistItem(.lyrics(LyricsItem(title: "S", slides: [" a ", "", "  "])))]
        XCTAssertNil(d.problem(kind: .kids))
        guard case .lyrics(let l) = d.cleaned().items[0].content else { return XCTFail() }
        XCTAssertEqual(l.slides, ["a"])

        var deck = DeckDraft(organizationId: org, name: "Deck")
        deck.slides = [DeckSlide.new(.text, existing: []), DeckSlide.new(.song, existing: [])]
        XCTAssertEqual(deck.problem, "Slide 1: is an empty text slide. Add some words or delete it.")
        deck.slides[0].content = .text(TextSlideContent(title: "Hi"))
        XCTAssertEqual(deck.problem, "Slide 2: needs a song chosen.")
        let ids = Set((0..<50).map { _ in DeckSlide.newId(existing: []) })
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("s_") && $0.count == 7 })
    }

    // MARK: expandSong (mirrors selfCheck() in songParsers.ts)

    func testExpandSongParity() {
        let sections = [
            SongSection(id: "s1", label: "Verse 1", text: "Amazing grace how sweet the sound\nThat saved a wretch like me"),
            SongSection(id: "s2", label: "Chorus", text: "My chains are gone"),
            SongSection(id: "s3", label: "Pre-Chorus", text: "Hold on"),
        ]
        func flat(_ s: [LyricSlide]) -> [String] { s.map { "\($0.label):\($0.text.replacingOccurrences(of: "\n", with: "/"))" } }
        // arrangement with a repeat and an unknown id, one line per slide
        XCTAssertEqual(flat(SongExpander.expand(sections: sections, arrangement: ["s1", "s2", "s1", "zz"], linesPerSlide: 1)), [
            "Verse 1:Amazing grace how sweet the sound", "Verse 1:That saved a wretch like me", "Chorus:My chains are gone",
            "Verse 1:Amazing grace how sweet the sound", "Verse 1:That saved a wretch like me",
        ])
        // no arrangement: every section once, one slide per section
        XCTAssertEqual(SongExpander.expand(sections: sections, arrangement: nil, linesPerSlide: 0).count, 3)
        XCTAssertEqual(SongExpander.expand(sections: sections, arrangement: [], linesPerSlide: 0).count, 3)
        // two lines per slide splits uneven sections
        let four = [SongSection(id: "a", label: "V", text: "1\n2\n3\n4\n5")]
        XCTAssertEqual(flat(SongExpander.expand(sections: four, arrangement: nil, linesPerSlide: 2)), ["V:1/2", "V:3/4", "V:5"])
        // empty and whitespace-only sections are skipped; surrounding blank lines and spaces are trimmed; CR removed
        let messy = [SongSection(id: "a", label: "A", text: "  \n \n"), SongSection(id: "b", label: "B", text: "\n\n line one\r\nline two \n\n")]
        XCTAssertEqual(flat(SongExpander.expand(sections: messy, arrangement: nil, linesPerSlide: 0)), ["B:line one/line two"])
        // arrangement that names only unknown sections gives nothing
        XCTAssertTrue(SongExpander.expand(sections: sections, arrangement: ["nope"], linesPerSlide: 0).isEmpty)
    }

    func testSongDecodeIsLenient() throws {
        let json = ##"{"id":"11111111-1111-4111-8111-111111111111","organization_id":null,"title":"T","authors":null,"ccli_number":"123","copyright":null,"sections":[{"id":"s1","label":"V","text":"a"}],"arrangement":null,"lines_per_slide":2,"source":"manual","created_at":"2026-10-21T10:00:00Z","updated_at":"2026-10-21T10:00:00Z"}"##
        let s = try ContentJSON.decoder().decode(Song.self, from: Data(json.utf8))
        XCTAssertEqual(s.ccliNumber, "123"); XCTAssertEqual(s.linesPerSlide, 2); XCTAssertEqual(s.lyricSlides.count, 1)
        // old two-field shape still decodes (title only)
        let light = try ChurchJSON.decoder().decode(Song.self, from: Data(##"{"id":"11111111-1111-4111-8111-111111111111","title":"T"}"##.utf8))
        XCTAssertEqual(light.title, "T"); XCTAssertTrue(light.sections.isEmpty)
    }

    // MARK: Outlines and rendering rules

    func testDeckOutlineMatchesTVLabels() {
        let song = Song(id: UUID(), title: "Amazing Grace", sections: [SongSection(id: "s1", label: "Verse 1", text: "a\nb"), SongSection(id: "s2", label: " ", text: "c")], linesPerSlide: 0)
        let songs = Song.lookup([song])
        let sid = song.id.uuidString.lowercased()
        let slides = [
            DeckSlide(id: "1", content: .countdown(CountdownSettings(title: "Starts in", mode: .duration, seconds: 60))),
            DeckSlide(id: "2", content: .text(TextSlideContent(title: " ", body: "\nFirst body line\nsecond"))),
            DeckSlide(id: "3", content: .song(SongSlideContent(songId: sid, showTitle: true))),
            DeckSlide(id: "4", content: .song(SongSlideContent(songId: "gone", showTitle: true))),
            DeckSlide(id: "5", content: .media(MediaSlideContent(mediaKind: .video))),
            DeckSlide(id: "6", content: .stream(StreamSlideContent(title: ""))),
            DeckSlide(id: "7", content: .blank(BlankSlideContent())),
        ]
        // text: blank title falls back to the first line of the body, which is empty here -> "Text" (the TV looks at the first line only)
        XCTAssertEqual(DeckOutline.labels(for: slides, songs: songs), [
            "Countdown: Starts in", "Text", "Amazing Grace (title)", "Amazing Grace · Verse 1", "Amazing Grace · Part 2", "Video", "Live stream", "Blank",
        ])
        XCTAssertEqual(DeckOutline.entries(for: slides, songs: songs).map(\.slideId), ["1", "2", "3", "3", "3", "5", "6", "7"])
        XCTAssertEqual(DeckOutline.frames(for: slides, songs: songs).count, 9, "includes the placeholder frame for the song that is gone")

        let items = [PlaylistItem.newVideo(), PlaylistItem(.lyrics(LyricsItem(title: "x", songId: sid, showTitle: true))), PlaylistItem(.countdown(CountdownItem(countdown: CountdownSettings(title: ""))))]
        XCTAssertEqual(PlaylistOutline.labels(for: items, songs: songs), ["Video", "Amazing Grace (title)", "Amazing Grace · Part 1 of 2", "Amazing Grace · Part 2 of 2", "Countdown"])
    }

    func testRenderRules() {
        // background order
        let slideBg = SlideBackground.solid("#111111"), deckBg = SlideBackground.solid("#222222"), themeBg = SlideBackground.solid("#333333")
        XCTAssertEqual(BackgroundResolver.resolve(slide: slideBg, deck: deckBg, theme: themeBg).color, "#111111")
        XCTAssertEqual(BackgroundResolver.resolve(slide: nil, deck: deckBg, theme: themeBg).color, "#222222")
        XCTAssertEqual(BackgroundResolver.resolve(slide: .image(mediaId: "", url: ""), deck: nil, theme: themeBg).color, "#333333")
        XCTAssertEqual(BackgroundResolver.resolve(slide: nil, deck: nil, theme: nil).color, SlideMetrics.defaultNavy)
        // text plans
        let t = ThemeConfig().resolved
        let plan = SlideRender.planText(.text(layout: .titleBody, title: "Hello", body: "World", align: nil, color: nil), theme: t)!
        XCTAssertEqual(plan.blocks.map(\.role), [.title, .body]); XCTAssertEqual(plan.blocks[0].size, 9); XCTAssertEqual(plan.top, 8)
        XCTAssertNil(SlideRender.planText(.blank(color: "#000000"), theme: t))
        let lower = SlideRender.planText(.text(layout: .lowerThird, title: "A", body: "B", align: nil, color: nil), theme: t)!
        XCTAssertEqual(lower.top, 66)
        // auto-fit shrinks long text but never below the floor, short text stays 1
        XCTAssertEqual(SlideRender.fitScale(plan, theme: t, shape: .landscape), 1)
        let long = SlideRender.planText(.lyric(text: String(repeating: "word ", count: 120), label: "V", n: 1, count: 1), theme: t)!
        let k = SlideRender.fitScale(long, theme: t, shape: .landscape)
        XCTAssertLessThan(k, 1); XCTAssertGreaterThanOrEqual(k, SlideRender.minScale(long))
        XCTAssertLessThan(SlideRender.fitScale(long, theme: t, shape: .portrait), k + 0.0001)
        XCTAssertEqual(SlideRender.countdownText(300), "05:00"); XCTAssertEqual(SlideRender.countdownText(3700), "1:01:40")
        XCTAssertEqual(SlideRender.clock12("09:05"), "9:05 AM"); XCTAssertEqual(SlideRender.clock12("00:30"), "12:30 AM"); XCTAssertEqual(SlideRender.clock12("17:00"), "5:00 PM")
        XCTAssertEqual(SlideRender.wrapLines("aaaa bbbb cccc", size: 1, width: 9, charW: 1), 2)
        XCTAssertGreaterThan(ColorTools.contrast("#ffffff", "#000000"), 20)
        XCTAssertEqual(ColorTools.dimmed("#ffffff", 0.5), "#808080")
    }

    // MARK: Media library

    func testMediaLibraryBrowsing() {
        let root = MediaFolder(id: UUID(), module: "slides", name: "Series")
        let child = MediaFolder(id: UUID(), module: "slides", parentId: root.id, name: "Week 1")
        let items = [
            MediaItem(module: "slides", folderId: nil, title: "Top image", kind: .image, url: "u"),
            MediaItem(module: "slides", folderId: root.id, title: "Track", kind: .audio, url: "u"),
            MediaItem(module: "slides", folderId: child.id, title: "Graphic", kind: .image, url: "u"),
        ]
        let lib = MediaLibrary(module: .slides, items: items, folders: [root, child])
        XCTAssertEqual(lib.subfolders(of: nil).map(\.name), ["Series"])
        XCTAssertEqual(lib.files(in: root.id, kinds: [.audio]).map(\.title), ["Track"])
        XCTAssertEqual(lib.files(in: root.id, kinds: [.image]).count, 0)
        XCTAssertEqual(lib.breadcrumb(to: child.id).map(\.name), ["Series", "Week 1"])
        XCTAssertEqual(lib.count(in: root.id), 2)
        XCTAssertEqual(lib.count(in: root.id, kinds: [.audio]), 1)
        XCTAssertEqual(lib.search("gra").files.map(\.title), ["Graphic"])
        XCTAssertEqual(lib.search("week").folders.map(\.name), ["Week 1"])
        XCTAssertEqual(lib.search("   ").files.count, 0)
        XCTAssertNotNil(lib.item(id: items[0].id.uuidString))
        XCTAssertEqual(DemoMedia.parse(DemoMedia.url(.video, "112233", "445566"))?.color2, "#445566")
        XCTAssertNil(DemoMedia.parse("https://x/y.jpg"))
    }
}
