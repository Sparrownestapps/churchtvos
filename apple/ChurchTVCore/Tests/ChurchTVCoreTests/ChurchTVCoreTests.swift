import XCTest
@testable import ChurchTVCore

final class DecodingTests: XCTestCase {
    let decoder = ChurchJSON.decoder()

    func testScreenRow() throws {
        let json = """
        [{"id":"7b3f6c5e-1d2a-4c3b-8a9d-0e1f2a3b4c5d","organization_id":"11111111-2222-4333-8444-555555555555",
          "location_id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","group_id":null,"name":"Main Auditorium","orientation":"landscape",
          "default_module":"slides","model":"AFTGAZL","app_version":"1.5.0","last_seen_at":"2026-10-22T14:03:11.123456+00:00"}]
        """.data(using: .utf8)!
        let screens = try decoder.decode([Screen].self, from: json)
        XCTAssertEqual(screens.count, 1)
        XCTAssertEqual(screens[0].name, "Main Auditorium")
        XCTAssertEqual(screens[0].appVersion, "1.5.0")
        XCTAssertNil(screens[0].groupId)
        XCTAssertNotNil(screens[0].lastSeenAt)
    }

    func testScreenStatusWithOutline() throws {
        let json = """
        {"screen_id":"7b3f6c5e-1d2a-4c3b-8a9d-0e1f2a3b4c5d","organization_id":"11111111-2222-4333-8444-555555555555",
         "module":"slides","state":"playing","title":"Sunday","item_label":"Verse 1 · Great Are You Lord","slide_index":2,"slide_count":4,
         "updated_at":"2026-10-22T14:03:11Z","outline":["Welcome","Great Are You Lord (title)","Verse 1","Chorus"],
         "ref_kind":"deck","ref_id":"22222222-2222-4222-8222-222222222222"}
        """.data(using: .utf8)!
        let s = try decoder.decode(ScreenStatus.self, from: json)
        XCTAssertEqual(s.state, .playing)
        XCTAssertEqual(s.outline?.count, 4)
        XCTAssertEqual(s.currentIndex, 2)
        XCTAssertEqual(s.slideText, "Slide 3 of 4")
        XCTAssertEqual(s.progress, 0.75, accuracy: 0.001)
        XCTAssertEqual(s.refKind, "deck")
    }

    func testStatusWithNullsAndUnknownState() throws {
        let json = """
        {"screen_id":"7b3f6c5e-1d2a-4c3b-8a9d-0e1f2a3b4c5d","organization_id":null,"module":null,"state":"somethingnew","title":null,
         "item_label":null,"slide_index":null,"slide_count":null,"updated_at":"2026-10-22 14:03:11.5+00","outline":null,"ref_kind":null,"ref_id":null}
        """.data(using: .utf8)!
        let s = try decoder.decode(ScreenStatus.self, from: json)
        XCTAssertEqual(s.state, .unknown)
        XCTAssertNil(s.slideText)
        XCTAssertNotNil(s.updatedAt)
    }

    func testSlideIndexIsClamped() {
        let s = ScreenStatus(screenId: UUID(), slideIndex: 99, slideCount: 5)
        XCTAssertEqual(s.currentIndex, 4)
    }

    func testMembershipWithEmbeddedOrganization() throws {
        let json = """
        [{"id":"99999999-9999-4999-8999-999999999999","organization_id":"11111111-2222-4333-8444-555555555555","role":"operator",
          "modules":["kids","signage","slides"],"site_ids":null,
          "organizations":{"id":"11111111-2222-4333-8444-555555555555","name":"Forward Church","slug":"forward"}}]
        """.data(using: .utf8)!
        let m = try decoder.decode([Membership].self, from: json)
        XCTAssertEqual(m[0].role, .operator)
        XCTAssertEqual(m[0].organizations?.name, "Forward Church")
        XCTAssertNil(m[0].siteIds)
        XCTAssertTrue(m[0].role.canControl)
        XCTAssertFalse(m[0].role.canEditContent)
    }

    func testOccurrenceRowsForDecksAndPlaylists() throws {
        let deck = """
        [{"series_id":"33333333-3333-4333-8333-333333333333","location_id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","on_date":"2026-10-25",
          "starts_at":"2026-10-25T14:30:00+00:00","ends_at":"2026-10-25T16:00:00+00:00","deck_id":"44444444-4444-4444-8444-444444444444",
          "occurrence_no":3,"is_override":false}]
        """.data(using: .utf8)!
        let rows = try decoder.decode([OccurrenceRow].self, from: deck)
        XCTAssertEqual(rows[0].occurrenceNo, 3)
        XCTAssertNotNil(rows[0].deckId)
        XCTAssertNil(rows[0].playlistId)
        let kids = """
        [{"series_id":"33333333-3333-4333-8333-333333333333","location_id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","on_date":"2026-10-25",
          "starts_at":"2026-10-25T14:30:00+00:00","ends_at":null,"playlist_id":"55555555-5555-4555-8555-555555555555","occurrence_no":1,"is_override":true}]
        """.data(using: .utf8)!
        let k = try decoder.decode([OccurrenceRow].self, from: kids)
        XCTAssertNil(k[0].endsAt)
        XCTAssertNotNil(k[0].playlistId)
    }

    func testDeckAndPlaylistAndEntitlementRows() throws {
        let decks = try decoder.decode([Deck].self, from: #"[{"id":"44444444-4444-4444-8444-444444444444","name":"Sunday"}]"#.data(using: .utf8)!)
        XCTAssertEqual(decks[0].name, "Sunday")
        let lists = try decoder.decode([PlaylistRef].self, from: #"[{"id":"55555555-5555-4555-8555-555555555555","name":"Week 1"}]"#.data(using: .utf8)!)
        XCTAssertEqual(lists[0].name, "Week 1")
        let e = try decoder.decode(Entitlement.self, from: #"{"module":"slides","status":"trialing"}"#.data(using: .utf8)!)
        XCTAssertTrue(e.isUsable)
        XCTAssertFalse(Entitlement(module: "kids", status: "canceled").isUsable)
    }
}

final class CommandTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testSimpleCommands() throws {
        let id = UUID(uuidString: "7B3F6C5E-1D2A-4C3B-8A9D-0E1F2A3B4C5D")!
        let p = try json(SendCommandParams(screenId: id, command: .next))
        XCTAssertEqual(p["p_screen_id"] as? String, "7b3f6c5e-1d2a-4c3b-8a9d-0e1f2a3b4c5d")
        XCTAssertEqual(p["p_command"] as? String, "next")
        XCTAssertEqual((p["p_payload"] as? [String: Any])?.count, 0)
        XCTAssertEqual(RemoteCommand.clearMessage.name, "clear_message")
        XCTAssertEqual(RemoteCommand.previous.name, "previous")
        XCTAssertEqual(RemoteCommand.stop.name, "stop")
    }

    func testJumpAndBlankPayloads() {
        XCTAssertEqual(RemoteCommand.jump(index: 4).payload, ["index": .int(4)])
        XCTAssertEqual(RemoteCommand.jump(index: -3).payload, ["index": .int(0)])
        XCTAssertEqual(RemoteCommand.blank(on: true).payload, ["on": .bool(true)])
        XCTAssertEqual(RemoteCommand.blank(on: nil).payload, [:])   // toggle
    }

    func testStartPayloadClampsMinutes() {
        let id = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        XCTAssertEqual(RemoteCommand.start(kind: .deck, id: id, minutes: 1).payload["minutes"], .int(5))
        XCTAssertEqual(RemoteCommand.start(kind: .playlist, id: id, minutes: 99999).payload["minutes"], .int(1440))
        XCTAssertEqual(RemoteCommand.start(kind: .deck, id: id, minutes: 60).payload["kind"], .string("deck"))
        XCTAssertEqual(RemoteCommand.start(kind: .deck, id: id, minutes: 60).payload["id"], .string("44444444-4444-4444-8444-444444444444"))
    }

    func testMessagePayloadAndValidation() {
        let m = RemoteCommand.message(text: "  Hello  ", seconds: 2, background: nil)
        XCTAssertEqual(m.payload["text"], .string("Hello"))
        XCTAssertEqual(m.payload["seconds"], .int(5))
        XCTAssertNil(m.payload["background"])
        XCTAssertEqual(RemoteCommand.message(text: "x", seconds: 9999, background: "#112233").payload["seconds"], .int(300))
        XCTAssertNotNil(RemoteCommand.message(text: "   ", seconds: 30, background: nil).validationError)
        XCTAssertNotNil(RemoteCommand.message(text: String(repeating: "a", count: 201), seconds: 30, background: nil).validationError)
        XCTAssertNil(m.validationError)
    }

    func testEncodedMessageParams() throws {
        let id = UUID()
        let p = try json(SendCommandParams(screenId: id, command: .message(text: "Hi", seconds: 30, background: "#1B2A4A")))
        let payload = p["p_payload"] as! [String: Any]
        XCTAssertEqual(payload["text"] as? String, "Hi")
        XCTAssertEqual(payload["seconds"] as? Int, 30)
        XCTAssertEqual(payload["background"] as? String, "#1B2A4A")
    }
}

final class HealthTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlineWindowIs90Seconds() {
        XCTAssertTrue(ScreenHealth.isOnline(lastSeen: now.addingTimeInterval(-90), now: now))
        XCTAssertFalse(ScreenHealth.isOnline(lastSeen: now.addingTimeInterval(-91), now: now))
        XCTAssertFalse(ScreenHealth.isOnline(lastSeen: nil, now: now))
    }

    func testStaleAfter60Seconds() {
        XCTAssertFalse(ScreenHealth.isStatusStale(updatedAt: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(ScreenHealth.isStatusStale(updatedAt: now.addingTimeInterval(-61), now: now))
        XCTAssertTrue(ScreenHealth.isStatusStale(updatedAt: nil, now: now))
    }

    func testDisplayState() {
        let id = UUID()
        func info(seen: TimeInterval, updated: TimeInterval, state: PlaybackState) -> ScreenInfo {
            ScreenInfo(screen: Screen(id: id, appVersion: "1.5.0", lastSeenAt: now.addingTimeInterval(-seen)),
                       status: ScreenStatus(screenId: id, state: state, updatedAt: now.addingTimeInterval(-updated)))
        }
        XCTAssertEqual(info(seen: 200, updated: 5, state: .playing).displayState(now: now), .offline)
        XCTAssertEqual(info(seen: 5, updated: 5, state: .playing).displayState(now: now), .playing)
        XCTAssertEqual(info(seen: 5, updated: 5, state: .blank).displayState(now: now), .blank)
        XCTAssertEqual(info(seen: 5, updated: 5, state: .message).displayState(now: now), .message)
        XCTAssertEqual(info(seen: 5, updated: 120, state: .playing).displayState(now: now), .stale)
        XCTAssertEqual(ScreenInfo(screen: Screen(id: id, lastSeenAt: now)).displayState(now: now), .idle)
    }

    func testVersionComparison() {
        XCTAssertEqual(AppVersion.compare("1.5.0", "1.5.0"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("1.5", "1.5.0"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("1.10.0", "1.9.2"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("1.4.9", "1.5.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("v2.0.0", "1.99.99"), .orderedDescending)
        XCTAssertEqual(AppVersion.components("1.5.0-beta2"), [1, 5, 0])
    }

    func testRemoteSupportNeeds150() {
        XCTAssertTrue(ScreenHealth.supportsRemote(appVersion: "1.5.0"))
        XCTAssertTrue(ScreenHealth.supportsRemote(appVersion: "1.5.3"))
        XCTAssertTrue(ScreenHealth.supportsRemote(appVersion: "2.0"))
        XCTAssertFalse(ScreenHealth.supportsRemote(appVersion: "1.4.9"))
        XCTAssertFalse(ScreenHealth.supportsRemote(appVersion: "1.4.1"))
        XCTAssertFalse(ScreenHealth.supportsRemote(appVersion: nil))
    }

    func testAgoFormatting() {
        XCTAssertEqual(Formatting.ago(now.addingTimeInterval(-2), now: now), "just now")
        XCTAssertEqual(Formatting.ago(now.addingTimeInterval(-30), now: now), "30 s ago")
        XCTAssertEqual(Formatting.ago(now.addingTimeInterval(-300), now: now), "5 min ago")
        XCTAssertEqual(Formatting.ago(nil, now: now), "never")
        XCTAssertEqual(Formatting.clock(90), "1:30")
    }
}

final class MediaTests: XCTestCase {
    func testStoragePathHasOrgPrefixAndRandomPart() {
        let org = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let u = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        XCTAssertEqual(MediaPath.make(organizationId: org, filename: "IMG 0001 (1).jpg", uuid: u),
                       "11111111-2222-4333-8444-555555555555/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee-IMG_0001__1_.jpg")
    }

    func testMediaRowEncoding() throws {
        let org = UUID(), folder = UUID()
        let row = NewMediaRow(organizationId: org, module: "slides", title: "Easter", kind: .image, storagePath: "p", url: "https://x/y", sizeBytes: 1234, folderId: folder)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as! [String: Any]
        XCTAssertEqual(obj["module"] as? String, "slides")
        XCTAssertEqual(obj["kind"] as? String, "image")
        XCTAssertEqual(obj["size_bytes"] as? Int, 1234)
        XCTAssertEqual(obj["folder_id"] as? String, folder.uuidString)
        let root = NewMediaRow(organizationId: org, module: "kids", title: "t", kind: .video, storagePath: "p", url: "u", sizeBytes: 1, folderId: nil)
        let o2 = try JSONSerialization.jsonObject(with: JSONEncoder().encode(root)) as! [String: Any]
        XCTAssertTrue(o2["folder_id"] is NSNull)
    }
}

final class ScheduleTests: XCTestCase {
    func testOpenEndedOneOffEndsWhereNextStarts() {
        let tz = TimeZone(identifier: "America/Toronto")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let screen = ScreenInfo(screen: Screen(id: id), timeZoneId: tz.identifier)
        let (start, _) = ScheduleBuilder.dayBounds(now: now, timeZone: tz)
        let a = ScheduleEntry(id: "a", screenId: id, module: .kids, title: "A", starts: start.addingTimeInterval(3600), ends: nil, source: .oneOff)
        let b = ScheduleEntry(id: "b", screenId: id, module: .kids, title: "B", starts: start.addingTimeInterval(7200), ends: nil, source: .oneOff)
        let out = ScheduleBuilder.today([b, a], screens: [screen], now: now)
        XCTAssertEqual(out.map(\.title), ["A", "B"])
        XCTAssertEqual(out[0].ends, b.starts)
    }

    func testYesterdayEntryIsDropped() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let screen = ScreenInfo(screen: Screen(id: id), timeZoneId: "UTC")
        let old = ScheduleEntry(id: "o", screenId: id, module: .slides, title: "Old", starts: now.addingTimeInterval(-3 * 86400), ends: now.addingTimeInterval(-2 * 86400), source: .oneOff)
        XCTAssertTrue(ScheduleBuilder.today([old], screens: [screen], now: now).isEmpty)
    }
}

final class MockServiceTests: XCTestCase {
    func testDemoCommandsMoveStatus() async throws {
        let mock = MockService()
        let church = try await mock.loadChurches()[0]
        let screens = try await mock.listScreens(organizationId: church.id)
        XCTAssertEqual(screens.count, 4)
        let main = screens[0]
        let before = main.status?.slideIndex ?? -1
        try await mock.send(.next, to: main.id)
        var after = try await mock.fetchStatuses(organizationId: church.id)[main.id]
        XCTAssertEqual(after?.slideIndex, before + 1)
        try await mock.send(.jump(index: 7), to: main.id)
        try await mock.send(.blank(on: true), to: main.id)
        after = try await mock.fetchStatuses(organizationId: church.id)[main.id]
        XCTAssertEqual(after?.slideIndex, 7)
        XCTAssertEqual(after?.state, .blank)
        try await mock.send(.stop, to: main.id)
        after = try await mock.fetchStatuses(organizationId: church.id)[main.id]
        XCTAssertEqual(after?.state, .idle)
    }

    func testDemoHasOfflineAndOldVersionScreens() async throws {
        let mock = MockService()
        let screens = try await mock.listScreens(organizationId: MockService.churchId)
        XCTAssertTrue(screens.contains { !$0.isOnline() })
        XCTAssertTrue(screens.contains { !$0.supportsRemote })
    }

    func testDemoRateLimit() async throws {
        let mock = MockService()
        let id = MockService.id(1)
        var failed = false
        for _ in 0..<25 { do { try await mock.send(.next, to: id) } catch { failed = true } }
        XCTAssertTrue(failed)
    }
}
