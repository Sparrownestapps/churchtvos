import XCTest
@testable import ChurchTVCore

final class NdiTests: XCTestCase {
    private func assertStable<T: Codable>(_ type: T.Type, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let value = try ContentJSON.decoder().decode(T.self, from: Data(json.utf8))
        let out = try JSONDecoder().decode(RawJSON.self, from: try ContentJSON.encoder().encode(value))
        XCTAssertEqual(out, try RawJSON.parse(json), "round trip changed \(json)", file: file, line: line)
    }

    private let full = ##"{"type":"ndi","title":"Main camera","source":"STUDIO-PC (Camera 1)","address":"192.168.1.50:5961","audio":false,"fit":"fit","fallback":"message","fallback_text":"Camera is offline, back soon","max_wait_seconds":15,"seconds":null}"##

    func testItemRoundTrip() throws {
        try assertStable(PlaylistItem.self, full)
        try assertStable(PlaylistItem.self, ##"{"type":"ndi","title":"","source":"A (B)","audio":true,"fit":"fill","fallback":"skip","max_wait_seconds":120,"seconds":30}"##)
        // the contract example with an unknown key
        try assertStable(PlaylistItem.self, ##"{"type":"ndi","title":"X","source":"A (B)","audio":false,"fit":"fit","fallback":"skip","max_wait_seconds":3,"seconds":null,"future":{"a":[1,2]}}"##)
    }

    func testSlideRoundTrip() throws {
        try assertStable(DeckSlide.self, ##"{"id":"s_a1b2c","kind":"ndi","title":"Cam","source":"A (B)","address":"cam.local","audio":false,"fit":"fill","fallback":"message","fallback_text":"Back soon","max_wait_seconds":20,"seconds":45,"notes":"n"}"##)
        try assertStable(DeckSlide.self, ##"{"id":"s_a1b2c","kind":"ndi","title":"","source":"A (B)","audio":false,"fit":"fit","fallback":"skip","max_wait_seconds":15,"seconds":null,"background":{"type":"color","color":"#112233"},"zzz":1}"##)
    }

    func testDefaultsAndDecoding() throws {
        let item = try ContentJSON.decoder().decode(PlaylistItem.self, from: Data(##"{"type":"ndi","source":"A (B)"}"##.utf8))
        guard case .ndi(let n) = item.content else { return XCTFail("not ndi") }
        XCTAssertEqual(n.ndi, NdiSettings(title: "", source: "A (B)"))
        XCTAssertEqual(n.ndi.fit, .fit); XCTAssertEqual(n.ndi.fallback, .skip); XCTAssertEqual(n.ndi.maxWaitSeconds, 15); XCTAssertNil(n.ndi.seconds); XCTAssertFalse(n.ndi.audio)
        XCTAssertEqual(item.typeName, .ndi)
        // a new item has the contract defaults and is invalid until a source is typed
        let fresh = PlaylistItem.newNdi()
        XCTAssertNotNil(fresh.problem)
        XCTAssertEqual(DeckSlide.new(.ndi, existing: []).kind, .ndi)
    }

    func testNewSlideWritesContractFields() {
        let o = DeckSlide.new(.ndi, existing: []).object
        XCTAssertEqual(o["kind"], .string("ndi")); XCTAssertEqual(o["title"], .string("")); XCTAssertEqual(o["source"], .string(""))
        XCTAssertEqual(o["audio"], .bool(false)); XCTAssertEqual(o["fit"], .string("fit")); XCTAssertEqual(o["fallback"], .string("skip"))
        XCTAssertEqual(o["max_wait_seconds"], .number(15)); XCTAssertEqual(o["seconds"], .null)
        XCTAssertNil(o["address"]); XCTAssertNil(o["fallback_text"])
    }

    func testValidationMatchesSQLAndWeb() {
        func p(_ edit: (inout NdiSettings) -> Void) -> String? { var s = NdiSettings(source: "A (B)"); edit(&s); return s.problem }
        XCTAssertNil(p { _ in })
        XCTAssertNotNil(p { $0.source = "   " })
        XCTAssertNotNil(p { $0.source = String(repeating: "x", count: 201) })
        XCTAssertNil(p { $0.source = String(repeating: "x", count: 200) })
        for ok in ["", "192.168.1.50", "192.168.1.50:5961", "cam-1.local", "host:1", "host:65535", "A"] { XCTAssertTrue(NdiSettings.isValidAddress(ok), ok) }
        for bad in ["a b", "host:0", "host:65536", "host:123456", "-host", "host-", ":5961", "host:", "http://x", "a/b"] { XCTAssertFalse(NdiSettings.isValidAddress(bad), bad) }
        XCTAssertNotNil(p { $0.address = "bad address" })
        XCTAssertNotNil(p { $0.maxWaitSeconds = 2 }); XCTAssertNil(p { $0.maxWaitSeconds = 3 })
        XCTAssertNil(p { $0.maxWaitSeconds = 120 }); XCTAssertNotNil(p { $0.maxWaitSeconds = 121 })
        XCTAssertNotNil(p { $0.seconds = 0 }); XCTAssertNil(p { $0.seconds = 1 }); XCTAssertNil(p { $0.seconds = 86400 }); XCTAssertNotNil(p { $0.seconds = 86401 })
        XCTAssertNotNil(p { $0.fallback = .message; $0.fallbackText = String(repeating: "m", count: 201) })
        XCTAssertNil(p { $0.fallback = .skip; $0.fallbackText = String(repeating: "m", count: 201) })   // text only matters for "message"
    }

    func testCleanedDropsEmptyOptionals() {
        var s = NdiSettings(title: "  Cam ", source: " A (B) ", address: "  ", fallback: .skip, fallbackText: "ignored")
        var c = s.cleaned()
        XCTAssertEqual(c.title, "Cam"); XCTAssertEqual(c.source, "A (B)"); XCTAssertNil(c.address); XCTAssertNil(c.fallbackText)
        s.fallback = .message; s.fallbackText = "  back soon "; s.address = " 10.0.0.2:5961 "
        c = s.cleaned()
        XCTAssertEqual(c.fallbackText, "back soon"); XCTAssertEqual(c.address, "10.0.0.2:5961")
        // the playlist and deck drafts clean NDI entries on save
        let org = UUID()
        let draft = PlaylistDraft(organizationId: org, name: "L", items: [.init(.ndi(NdiItem(ndi: s)))])
        XCTAssertEqual(draft.cleaned().items[0].ndiSettings, c)
        let deck = DeckDraft(organizationId: org, name: "D", slides: [DeckSlide(id: "s_1", content: .ndi(s))])
        XCTAssertEqual(deck.cleaned().slides[0].ndiSettings, c)
        XCTAssertNotNil(PlaylistDraft(organizationId: org, name: "L", items: [.newNdi()]).problem(kind: .kids))
    }

    func testRulesGuard() {
        let a = NdiSettings(source: "A (B)"), b = NdiSettings(source: "C (D)")
        XCTAssertFalse(NdiRules.addsOrChanges(old: [a, b], new: [b]))        // removing is fine
        XCTAssertFalse(NdiRules.addsOrChanges(old: [a, b], new: [b, a]))     // reordering is fine
        XCTAssertTrue(NdiRules.addsOrChanges(old: [a], new: [a, b]))         // adding
        var changed = a; changed.audio = true
        XCTAssertTrue(NdiRules.addsOrChanges(old: [a], new: [changed]))      // changing
    }

    func testOrganizationDecodesFlag() throws {
        let id = "D0D0D0D0-0000-4000-8000-000000000001"
        func org(_ json: String) throws -> Organization { try ChurchJSON.decoder().decode(Organization.self, from: Data(json.utf8)) }
        XCTAssertFalse(try org(##"{"id":"\##(id)","name":"X","slug":"x"}"##).ndiEnabled)                  // older database: column absent
        XCTAssertFalse(try org(##"{"id":"\##(id)","name":"X","slug":null,"ndi_enabled":null}"##).ndiEnabled)
        XCTAssertFalse(try org(##"{"id":"\##(id)","name":"X","slug":"x","ndi_enabled":false}"##).ndiEnabled)
        XCTAssertTrue(try org(##"{"id":"\##(id)","name":"X","slug":"x","ndi_enabled":true}"##).ndiEnabled)
        // inside the membership payload the service selects
        let m = try ChurchJSON.decoder().decode(Membership.self, from: Data(##"{"id":"\##(id)","organization_id":"\##(id)","role":"admin","modules":["kids"],"site_ids":null,"organizations":{"id":"\##(id)","name":"X","slug":"x","ndi_enabled":true}}"##.utf8))
        XCTAssertEqual(m.organizations?.ndiEnabled, true)
    }

    func testFramesAndOutlines() {
        let slide = DeckSlide(id: "s_1", content: .ndi(NdiSettings(title: "", source: "STUDIO-PC (Camera 1)", fit: .fill)))
        XCTAssertEqual(SlideRender.frames(for: slide, songs: [:]), [.ndi(title: "", source: "STUDIO-PC (Camera 1)", fit: .fill)])
        XCTAssertEqual(DeckOutline.labels(for: [slide], songs: [:]), ["STUDIO-PC (Camera 1)"])
        let item = PlaylistItem(.ndi(NdiItem(ndi: NdiSettings(title: "Main camera", source: "A (B)"))))
        XCTAssertEqual(PlaylistOutline.labels(for: [item], songs: [:]), ["Main camera"])
    }

    func testDemoServiceFlagAndGuard() async throws {
        let s = MockService()
        let church = try await s.loadChurches()[0]
        XCTAssertEqual(church.organization.ndiEnabled, MockService.demoNdiEnabled)
        guard !MockService.demoNdiEnabled else { return }
        // flag off: adding an NDI entry is refused like the database trigger, an existing/other content saves fine
        let org = MockService.churchId
        let bad = PlaylistDraft(organizationId: org, name: "N", items: [PlaylistItem(.ndi(NdiItem(ndi: NdiSettings(source: "A (B)"))))])
        do { _ = try await s.createPlaylist(kind: .kids, draft: bad); XCTFail("should refuse") } catch { XCTAssertEqual((error as? ChurchError)?.message, NdiRules.notEnabledMessage) }
        let okDraft = PlaylistDraft(organizationId: org, name: "OK", items: [PlaylistItem.newCountdown()])
        _ = try await s.createPlaylist(kind: .kids, draft: okDraft)
        let deckBad = DeckDraft(organizationId: org, name: "D", slides: [DeckSlide(id: "s_1", content: .ndi(NdiSettings(source: "A (B)")))])
        do { _ = try await s.createDeck(draft: deckBad); XCTFail("should refuse") } catch { XCTAssertEqual((error as? ChurchError)?.message, NdiRules.notEnabledMessage) }
    }
}
