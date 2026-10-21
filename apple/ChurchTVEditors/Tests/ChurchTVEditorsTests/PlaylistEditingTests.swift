import XCTest
import ChurchTVCore
@testable import ChurchTVEditors

final class PlaylistEditingTests: XCTestCase {
    private let org = UUID()
    private func draft(name: String = "Week 3", items: [PlaylistItem] = [], isNew: Bool = true) -> PlaylistDraft {
        PlaylistDraft(isNew: isNew, organizationId: org, name: name, items: items)
    }
    private func image(_ t: String) -> PlaylistItem { PlaylistItem(.image(MediaClip(title: t, url: "https://x/\(t).png", mediaId: t, seconds: 5))) }

    // MARK: defaults

    func testNewItemDefaultsMatchTheWebsite() {
        let kidsImage = PlaylistEditing.newItem(.image, kind: .kids)
        guard case .image(let k) = kidsImage.content else { return XCTFail() }
        XCTAssertNil(k.seconds, "Kids pictures wait for Next")
        guard case .image(let s) = PlaylistEditing.newItem(.image, kind: .signage).content else { return XCTFail() }
        XCTAssertEqual(s.seconds, 10)
        guard case .stream(let st) = PlaylistEditing.newItem(.stream, kind: .signage).content else { return XCTFail() }
        XCTAssertEqual(st.seconds, 30)
        guard case .stream(let kt) = PlaylistEditing.newItem(.stream, kind: .kids).content else { return XCTFail() }
        XCTAssertNil(kt.seconds)
        guard case .countdown(let c) = PlaylistEditing.newItem(.countdown, kind: .kids).content else { return XCTFail() }
        XCTAssertEqual(c.countdown.atZero, .hold); XCTAssertEqual(c.countdown.ifPassed, .zero)
        XCTAssertEqual(c.countdown.effectiveMode, .duration); XCTAssertEqual(c.countdown.seconds, 300)
        guard case .sign(let sign) = PlaylistEditing.newItem(.sign, kind: .signage, branding: OrgBranding(primaryColor: "#112233")).content else { return XCTFail() }
        XCTAssertEqual(sign.background, "#112233")
    }

    func testYouTubeStartsLiveOnlyWithAChannel() {
        let withChannel = OrgBranding(youtubeChannelId: "UC123")
        guard case .youtube(let y) = PlaylistEditing.newItem(.youtube, kind: .kids, churchName: "Forward", branding: withChannel).content else { return XCTFail() }
        XCTAssertEqual(y.channelId, "UC123"); XCTAssertNil(y.videoId); XCTAssertEqual(y.title, "Forward · Live now")
        guard case .youtube(let n) = PlaylistEditing.newItem(.youtube, kind: .kids).content else { return XCTFail() }
        XCTAssertNil(n.channelId)
    }

    func testAddMenuOffersExactlyTheKindsItemTypes() {
        XCTAssertEqual(PlaylistKind.kids.itemTypes, [.video, .image, .countdown, .lyrics, .youtube, .stream])
        XCTAssertEqual(PlaylistKind.signage.itemTypes, [.image, .video, .sign, .stream])
        XCTAssertEqual(PlaylistEditorLabels.menuLabel(.image, kind: .kids), "Picture")
        XCTAssertEqual(PlaylistEditorLabels.menuLabel(.image, kind: .signage), "Image")
    }

    // MARK: validation

    func testSaveNeedsNameValidItemsAndChange() {
        let original = draft(name: "Week 3", items: [image("a")], isNew: false)
        XCTAssertFalse(PlaylistEditing.canSave(draft: original, original: original, kind: .kids), "unchanged")
        var d = original; d.name = "  "
        XCTAssertFalse(PlaylistEditing.canSave(draft: d, original: original, kind: .kids), "blank name")
        d = original; d.items.append(PlaylistEditing.newItem(.video, kind: .kids))
        XCTAssertFalse(PlaylistEditing.canSave(draft: d, original: original, kind: .kids), "video without a file")
        XCTAssertEqual(d.problem(kind: .kids), "Item 2 needs a video chosen.")
        d = original; d.name = "Week 4"
        XCTAssertTrue(PlaylistEditing.canSave(draft: d, original: original, kind: .kids))
    }

    func testNewDraftWithNameCanBeSavedBeforeAnyEdit() {
        let d = draft(name: "Fresh")
        XCTAssertTrue(PlaylistEditing.canSave(draft: d, original: d, kind: .kids))
        XCTAssertFalse(PlaylistEditing.hasChanges(draft: d, original: d))
    }

    // MARK: reorder / duplicate

    func testMoveMatchesArrayMoveSemantics() {
        let items = ["a", "b", "c", "d"].map(image)
        func titles(_ x: [PlaylistItem]) -> [String] { x.map(\.title) }
        XCTAssertEqual(titles(PlaylistEditing.moved(items, from: [0], to: 3)), ["b", "c", "a", "d"])
        XCTAssertEqual(titles(PlaylistEditing.moved(items, from: [3], to: 0)), ["d", "a", "b", "c"])
        XCTAssertEqual(titles(PlaylistEditing.moved(items, from: [1], to: 4)), ["a", "c", "d", "b"])
        XCTAssertEqual(titles(PlaylistEditing.moved(items, from: [1, 2], to: 0)), ["b", "c", "a", "d"])
        var native = items; native.move(fromOffsets: [1, 2], toOffset: 4)
        XCTAssertEqual(titles(PlaylistEditing.moved(items, from: [1, 2], to: 4)), titles(native))
    }

    func testDuplicateInsertsACopyWithNewIdentityAndKeepsUnknownKeys() throws {
        let json = try RawJSON.parse(#"{"type":"stream","title":"Live","url":"https://a/b.m3u8","seconds":null,"audio":false,"fallback":"skip","future_key":{"x":1}}"#)
        var items = [PlaylistItem(object: json.objectValue!), image("b")]
        PlaylistEditing.duplicate(at: 0, in: &items)
        XCTAssertEqual(items.count, 3)
        XCTAssertNotEqual(items[0].uid, items[1].uid)
        XCTAssertEqual(items[0].object, items[1].object)
        XCTAssertEqual(items[1].object["future_key"], json["future_key"])
        PlaylistEditing.duplicate(at: 9, in: &items)
        XCTAssertEqual(items.count, 3)
    }

    func testUnknownItemSurvivesReorderAndEditsOfOthers() throws {
        let raw = try RawJSON.parse(#"{"type":"hologram","depth":3,"nested":[1,2]}"#).objectValue!
        var d = draft(items: [image("a"), PlaylistItem(object: raw), image("b")])
        d.items = PlaylistEditing.moved(d.items, from: [1], to: 0)
        if case .image(var c) = d.items[1].content { c.seconds = 9; d.items[1].content = .image(c) }
        guard case .unknown(let u) = d.items[0].content else { return XCTFail() }
        XCTAssertEqual(u.raw, raw)
        XCTAssertNil(d.items[0].problem)
        XCTAssertEqual(d.cleaned().items[0].object, raw)
    }

    func testLegacyCountdownIsNotRewrittenUntilEdited() throws {
        let raw = try RawJSON.parse(#"{"type":"countdown","title":"Start","seconds":120}"#).objectValue!
        let item = PlaylistItem(object: raw)
        XCTAssertEqual(item.object["at_zero"], nil)
        guard case .countdown(let c) = item.content else { return XCTFail() }
        XCTAssertEqual(c.countdown.effectiveAtZero, .next)
        XCTAssertEqual(item.object["mode"], nil)
    }

    // MARK: duration

    func testTotalDurationCountsKnownTimesOnly() {
        var countdown = CountdownSettings.new; countdown.atZero = .next; countdown.seconds = 60
        let items: [PlaylistItem] = [
            image("a"),                                                       // 5 s
            PlaylistItem(.sign(SignItem(title: "t", seconds: 10))),           // 10 s
            PlaylistItem(.countdown(CountdownItem(countdown: countdown))),    // 60 s (moves on by itself)
            PlaylistEditing.newItem(.video, kind: .kids),                     // unknown
            PlaylistEditing.newItem(.countdown, kind: .kids),                 // holds at zero: unknown
        ]
        let t = PlaylistEditing.totalSeconds(items)
        XCTAssertEqual(t.seconds, 75); XCTAssertEqual(t.unknown, 2)
        XCTAssertEqual(PlaylistEditing.durationText(75), "1 min 15 s")
        XCTAssertEqual(PlaylistEditing.durationText(45), "45 s")
        XCTAssertEqual(PlaylistEditing.durationText(3900), "1 h 5 min")
        XCTAssertEqual(PlaylistEditing.summary([]), "0 items")
        XCTAssertTrue(PlaylistEditing.summary(items).hasPrefix("5 items"))
    }

    // MARK: lyrics source switching

    func testSwitchingLyricsSourceKeepsBothSides() {
        let typed = LyricsItem(title: "My song", slides: ["one", "two"], showTitle: true)
        var stash = LyricsStash(typed)
        var item = stash.switched(typed, toLibrary: true)
        XCTAssertTrue(item.isLibrary); XCTAssertEqual(item.songId, ""); XCTAssertEqual(item.showTitle, true)
        item.songId = "abc"; item.title = "Library Song"
        item = stash.switched(item, toLibrary: false)
        XCTAssertFalse(item.isLibrary); XCTAssertEqual(item.slides, ["one", "two"]); XCTAssertEqual(item.title, "My song")
        item = stash.switched(item, toLibrary: true)
        XCTAssertEqual(item.songId, "abc"); XCTAssertEqual(item.title, "Library Song")
        XCTAssertEqual(stash.switched(item, toLibrary: true), item, "no-op when already there")
    }

    func testTypedLyricsBlankSlidesAreDroppedOnSave() {
        let d = draft(items: [PlaylistItem(.lyrics(LyricsItem(title: "S", slides: ["a", "  ", "", "b\nc"])))])
        guard case .lyrics(let l) = d.cleaned().items[0].content else { return XCTFail() }
        XCTAssertEqual(l.slides, ["a", "b\nc"])
        XCTAssertEqual(TypedLyrics.savedCount(["a", " ", ""]), 1)
        XCTAssertEqual(TypedLyrics.split("one\ntwo\n\n\nthree"), ["one\ntwo", "three"])
    }

    func testLibraryLyricsWithoutSongIsInvalid() {
        let d = draft(items: [PlaylistItem(.lyrics(LyricsItem(title: "", songId: "")))])
        XCTAssertNotNil(d.problem(kind: .kids))
    }

    // MARK: YouTube

    func testYouTubeLinkParsing() {
        let id = "dQw4w9WgXcQ"
        XCTAssertEqual(YouTubeLink.parseId(id), id)
        XCTAssertEqual(YouTubeLink.parseId("https://www.youtube.com/watch?v=\(id)&t=5"), id)
        XCTAssertEqual(YouTubeLink.parseId("https://youtu.be/\(id)?si=x"), id)
        XCTAssertEqual(YouTubeLink.parseId("https://www.youtube.com/live/\(id)"), id)
        XCTAssertEqual(YouTubeLink.parseId("https://www.youtube.com/shorts/\(id)"), id)
        XCTAssertEqual(YouTubeLink.parseId("https://www.youtube.com/embed/\(id)"), id)
        XCTAssertNil(YouTubeLink.parseId("not a link"))
        XCTAssertNil(YouTubeLink.parseId("https://example.com/"))
        XCTAssertEqual(YouTubeLink.parseStart("12:30"), 750)
        XCTAssertEqual(YouTubeLink.parseStart("1:02:30"), 3750)
        XCTAssertNil(YouTubeLink.parseStart("abc")); XCTAssertNil(YouTubeLink.parseStart(""))
        XCTAssertEqual(YouTubeLink.startText(750), "12:30"); XCTAssertEqual(YouTubeLink.startText(3750), "1:02:30"); XCTAssertEqual(YouTubeLink.startText(nil), "")
    }

    // MARK: stream

    func testStreamLinkValidationAndTesting() {
        XCTAssertTrue(StreamLink.isValid("https://cdn.example.com/live.m3u8"))
        XCTAssertFalse(StreamLink.isValid("cdn.example.com/live.m3u8"))
        XCTAssertFalse(StreamLink.isValid("https://bad link"))
        XCTAssertNotNil(StreamLink.hint("example.com"))
        XCTAssertNotNil(StreamLink.hint("http://example.com/a.m3u8"), "http works for saving but gets a warning")
        XCTAssertNil(StreamLink.hint("https://example.com/a.m3u8"))
        XCTAssertNil(StreamLink.hint(""))
        XCTAssertTrue(StreamLink.evaluate(status: 200, body: "#EXTM3U\n#EXT-X-VERSION:3").isOK)
        XCTAssertTrue(StreamLink.evaluate(status: 200, body: "\n  #EXTM3U").isOK)
        XCTAssertFalse(StreamLink.evaluate(status: 200, body: "<html>").isOK)
        XCTAssertTrue(StreamLink.evaluate(status: 404, body: "").text.contains("404"))
        let d = draft(items: [PlaylistEditing.newItem(.stream, kind: .signage)])
        XCTAssertEqual(d.problem(kind: .signage), "Item 1 needs a stream link (starting with https://).")
    }

    func testStreamTestWithoutLinkExplains() async {
        let r = await StreamLink.test("nope")
        XCTAssertFalse(r.isOK)
    }
}
