import XCTest
@testable import ChurchTVCore

final class OperationsTests: XCTestCase {
    func testPairingCode() {
        XCTAssertEqual(PairingCode.normalize(" abc 123 "), "ABC123")
        XCTAssertEqual(PairingCode.normalize("a-b_c 1!2?3"), "ABC123")
        XCTAssertTrue(PairingCode.isComplete("rjh cm5"))
        XCTAssertFalse(PairingCode.isComplete("rjh"))
        XCTAssertEqual(PairingCode.display("abc123"), "ABC 123")
        XCTAssertEqual(PairingCode.display("ab"), "AB")
        XCTAssertEqual(PairingCode.display("abc1234567"), "ABC 123")
    }

    func testScreenRules() {
        XCTAssertTrue(ScreenRules.canManage(.owner)); XCTAssertTrue(ScreenRules.canManage(.admin))
        XCTAssertFalse(ScreenRules.canManage(.editor)); XCTAssertFalse(ScreenRules.canManage(.operator))
        XCTAssertEqual(ScreenRules.countLine(screens: 1, limit: 5), "1 screen of 5 allowed on your plan")
        XCTAssertEqual(ScreenRules.countLine(screens: 3, limit: nil), "3 screens")
        XCTAssertTrue(ScreenRules.atLimit(screens: 5, limit: 5)); XCTAssertFalse(ScreenRules.atLimit(screens: 4, limit: 5)); XCTAssertFalse(ScreenRules.atLimit(screens: 9, limit: nil))
    }

    func testScreenUpdatePayloadWritesExplicitNulls() throws {
        let s = ScreenSettings(screenId: UUID(), name: "  ", locationId: nil, orientation: .portraitFlipped, defaultModule: "off", groupId: nil, signageDefaultPlaylistId: nil, autoplay: true)
        let json = String(data: try JSONEncoder().encode(s.updatePayload), encoding: .utf8)!
        for key in ["\"name\":null", "\"location_id\":null", "\"group_id\":null", "\"signage_default_playlist_id\":null", "\"orientation\":\"portrait_flipped\"", "\"default_module\":\"off\"", "\"autoplay\":true"] {
            XCTAssertTrue(json.contains(key), "missing \(key) in \(json)")
        }
    }

    func testPeopleRulesMirrorTheWebsite() {
        let sites = [Site(id: UUID(), name: "Downtown"), Site(id: UUID(), name: "Eastside")]
        var d = AccessDraft.blank(modules: ["kids", "signage", "slides"])
        XCTAssertEqual(d.role, .editor); XCTAssertNil(d.siteIds)
        XCTAssertEqual(PeopleRules.problem(d, isInvite: true), "Enter a valid email address.")
        d.email = "  New.Person@Church.org "
        XCTAssertNil(PeopleRules.problem(d, isInvite: true))
        XCTAssertEqual(PeopleRules.insertRow(organizationId: UUID(), draft: d).email, "new.person@church.org")
        d.setAllSites(false)
        XCTAssertEqual(PeopleRules.problem(d, isInvite: false), "Choose at least one site, or pick all sites.")
        d.toggleSite(sites[0].id)
        XCTAssertNil(PeopleRules.problem(d, isInvite: false))
        d.toggleSite(sites[0].id)
        XCTAssertEqual(d.siteIds, [])
        d.setAllSites(true); XCTAssertNil(d.siteIds)
        d.toggleModule("kids"); XCTAssertEqual(d.modules, ["signage", "slides"])
        d.toggleModule("kids"); XCTAssertTrue(d.modules.contains("kids"))

        let org = UUID()
        let me = UUID()
        let m = Member(organizationId: org, userId: me, email: "a@b.org", role: .editor, modules: ["kids", "production"], siteIds: [sites[1].id])
        XCTAssertEqual(PeopleRules.summary(m, moduleNames: ["kids": "Kids", "slides": "Slides"], sites: sites), "Editor · Kids · Eastside · Active")
        let admin = Member(organizationId: org, email: "c@d.org", role: .admin, modules: [], siteIds: [sites[0].id])
        XCTAssertEqual(PeopleRules.summary(admin, moduleNames: [:], sites: sites), "Admin · All modules · All sites · Invited, not signed up yet")
        let none = Member(organizationId: org, userId: UUID(), email: "e@f.org", role: .operator, modules: [])
        XCTAssertTrue(PeopleRules.summary(none, moduleNames: ["kids": "Kids"], sites: sites).contains("No modules"))
        XCTAssertFalse(PeopleRules.canRemove(m, currentUserId: me)); XCTAssertTrue(PeopleRules.canRemove(admin, currentUserId: me))
        XCTAssertTrue(PeopleRules.canManage(.owner)); XCTAssertFalse(PeopleRules.canManage(.editor))
    }

    func testMembershipPayloadsEncodeNullSites() throws {
        let org = UUID()
        let d = AccessDraft(email: "X@y.org", role: .operator, modules: ["kids"], siteIds: nil)
        let insert = String(data: try JSONEncoder().encode(PeopleRules.insertRow(organizationId: org, draft: d)), encoding: .utf8)!
        XCTAssertTrue(insert.contains("\"site_ids\":null")); XCTAssertTrue(insert.contains("\"role\":\"operator\"")); XCTAssertTrue(insert.contains("\"email\":\"x@y.org\""))
        let update = String(data: try JSONEncoder().encode(MembershipUpdatePayload(d)), encoding: .utf8)!
        XCTAssertTrue(update.contains("\"site_ids\":null")); XCTAssertFalse(update.contains("email"))
        let site = UUID()
        let scoped = String(data: try JSONEncoder().encode(MembershipUpdatePayload(AccessDraft(email: "", role: .editor, modules: [], siteIds: [site]))), encoding: .utf8)!
        XCTAssertTrue(scoped.contains(site.uuidString.lowercased()))
    }

    func testMemberDecodes() throws {
        let json = """
        [{"id":"11111111-1111-4111-8111-111111111111","organization_id":"22222222-2222-4222-8222-222222222222","user_id":null,"email":"a@b.org","role":"owner","modules":["kids"],"site_ids":null,"created_at":"2026-10-01T12:00:00.5+00:00"}]
        """
        let list = try ContentJSON.decoder().decode([Member].self, from: Data(json.utf8))
        XCTAssertEqual(list.first?.role, .owner); XCTAssertNil(list.first?.userId); XCTAssertNil(list.first?.siteIds); XCTAssertNotNil(list.first?.createdAt)
    }

    func testPlanLiveRule() {
        let now = Date()
        func p(_ status: String, end: Double? = nil, grace: Double? = nil) -> PlanRow {
            PlanRow(module: "kids", status: status, tvLimit: 2, plan: "x", currentPeriodEnd: end.map { now.addingTimeInterval($0) }, graceEndsAt: grace.map { now.addingTimeInterval($0) })
        }
        XCTAssertTrue(p("active").isLive(now: now))
        XCTAssertTrue(p("trialing", end: 100).isLive(now: now)); XCTAssertTrue(p("trialing").isLive(now: now)); XCTAssertFalse(p("trialing", end: -1).isLive(now: now))
        XCTAssertTrue(p("past_due", grace: 100).isLive(now: now)); XCTAssertFalse(p("past_due").isLive(now: now)); XCTAssertFalse(p("canceled").isLive(now: now))
        XCTAssertFalse(p("active").isLive(churchSuspended: true, now: now))
    }

    func testBrandingKeepsUnknownKeysAndInherits() {
        var b = BrandingSettings(json: .object([
            "primary_color": .string("#1f3a5f"), "logo_url": .string("https://x/logo.png"), "future_key": .string("keep me"),
            "modules": .object(["kids": .object(["accent_color": .string("#112233"), "mystery": .bool(true)])]), "youtube_channel_id": .string("UC1234567890123456789012"),
        ]))
        XCTAssertEqual(b.look(.church).primaryColor, "#1f3a5f")
        XCTAssertNil(b.look(.church).object["modules"]); XCTAssertNil(b.look(.church).object["youtube_channel_id"])
        // module look inherits what it does not set
        let kids = b.effective(.kids)
        XCTAssertEqual(kids.primary, "#1f3a5f"); XCTAssertEqual(kids.accent, "#112233"); XCTAssertEqual(kids.logoURL, "https://x/logo.png")
        XCTAssertEqual(b.effective(.slides).accent, BrandingSettings.defaultAccent)
        XCTAssertEqual(b.effective(.church).splashSeconds, 5); XCTAssertFalse(b.effective(.church).splashEnabled)

        b.update(.church) { $0.accentColor = "#ABCDEF"; $0.splashEnabled = true; $0.splashSeconds = 9 }
        b.update(.slides) { $0.primaryColor = "#000000" }
        b.update(.kids) { $0.accentColor = nil }                 // "Use church colours": the override key is removed, unknown key stays
        let o = b.object
        XCTAssertEqual(o["future_key"]?.stringValue, "keep me")
        XCTAssertEqual(o["splash"]?["seconds"]?.intValue, 9); XCTAssertEqual(o["splash"]?["enabled"]?.boolValue, true)
        XCTAssertEqual(o["modules"]?["kids"]?["mystery"]?.boolValue, true); XCTAssertNil(o["modules"]?["kids"]?["accent_color"])
        XCTAssertEqual(o["modules"]?["slides"]?["primary_color"]?.stringValue, "#000000")
        XCTAssertEqual(o["youtube_channel_id"]?.stringValue, "UC1234567890123456789012")
        b.update(.slides) { $0.primaryColor = nil }              // a module look with nothing left disappears
        XCTAssertNil(b.object["modules"]?["slides"])
        b.update(.kids) { $0.object.removeAll() }
        XCTAssertNil(b.object["modules"])                        // and so does the empty modules object
        b.update(.church) { $0.splashSeconds = nil; $0.splashEnabled = nil }
        XCTAssertNil(b.object["splash"])
        XCTAssertEqual(b.effective(.church).accent, "#abcdef")   // normalised to lower case on read
    }

    func testBrandingValidation() {
        XCTAssertTrue(BrandingSettings.isValidYouTubeChannelId("UC1234567890123456789012"))
        XCTAssertTrue(BrandingSettings.isValidYouTubeChannelId("UCabc_def-ghi01234567890"))
        XCTAssertFalse(BrandingSettings.isValidYouTubeChannelId("UC123")); XCTAssertFalse(BrandingSettings.isValidYouTubeChannelId("XX1234567890123456789012"))
        XCTAssertNil(BrandingSettings.problem(name: "Grace", youtubeChannelId: ""))
        XCTAssertNotNil(BrandingSettings.problem(name: "  ", youtubeChannelId: ""))
        XCTAssertNotNil(BrandingSettings.problem(name: "Grace", youtubeChannelId: "nope"))
        XCTAssertEqual(BrandingSettings.clampSplashSeconds(1), 2); XCTAssertEqual(BrandingSettings.clampSplashSeconds(99), 30); XCTAssertEqual(BrandingSettings.clampSplashSeconds(7), 7)
        let org = UUID()
        let path = BrandingSettings.logoPath(organizationId: org, filename: "My Logo (1).png")
        XCTAssertTrue(path.hasPrefix("\(org.uuidString.lowercased())/branding/")); XCTAssertTrue(path.hasSuffix("My_Logo__1_.png"))
    }

    func testDemoOperationsEndToEnd() async throws {
        let demo = MockService()
        let org = MockService.churchId
        // screens
        var settings = try await demo.loadScreenSettings(organizationId: org)
        XCTAssertEqual(settings.count, 4)
        let first = try XCTUnwrap(settings.values.first { $0.name == "Kids Room 1" })
        var edited = first; edited.name = "Kids Room One"; edited.orientation = .portrait
        try await demo.updateScreen(edited)
        let list = await demo.overlayScreens(try await demo.listScreens(organizationId: org))
        XCTAssertEqual(list.first { $0.id == first.screenId }?.screen.name, "Kids Room One")
        XCTAssertEqual(list.first { $0.id == first.screenId }?.screen.orientation, "portrait")
        // pairing
        let loc = try await demo.listLocations(organizationId: org)[0]
        do { try await demo.claimScreen(code: "ZZZ999", locationId: loc.id, name: nil); XCTFail("should refuse") }
        catch { XCTAssertEqual((error as? ChurchError)?.message, "No TV is showing code ZZZ999") }
        try await demo.claimScreen(code: "dem 123", locationId: loc.id, name: "Atrium")
        settings = try await demo.loadScreenSettings(organizationId: org)
        XCTAssertEqual(settings.count, 5)
        XCTAssertTrue(settings.values.contains { $0.name == "Atrium" })
        let claimedId = try XCTUnwrap(settings.values.first { $0.name == "Atrium" }?.screenId)
        try await demo.releaseScreen(id: claimedId)
        let after = await demo.overlayScreens(try await demo.listScreens(organizationId: org))
        XCTAssertEqual(after.count, 4)
        // people: invite, duplicate refused, last owner protected
        let before = try await demo.listMembers(organizationId: org).count
        try await demo.inviteMember(organizationId: org, draft: AccessDraft(email: "Fresh@Example.org", role: .editor, modules: ["kids"]))
        do { try await demo.inviteMember(organizationId: org, draft: AccessDraft(email: "fresh@example.org", role: .editor, modules: ["kids"])); XCTFail("duplicate") } catch {}
        let members = try await demo.listMembers(organizationId: org)
        XCTAssertEqual(members.count, before + 1)
        let owner = try XCTUnwrap(members.first { $0.role == .owner })
        do { try await demo.removeMember(id: owner.id, organizationId: org); XCTFail("last owner") }
        catch { XCTAssertEqual((error as? ChurchError)?.message, "A church must keep at least one owner.") }
        try await demo.removeMember(id: try XCTUnwrap(members.first { $0.email == "fresh@example.org" }).id, organizationId: org)
        // branding
        var o = try await demo.loadOrganization(id: org)
        o.branding.update(.church) { $0.primaryColor = "#123456" }
        try await demo.saveOrganization(id: org, name: "Renamed", branding: o.branding)
        let o2 = try await demo.loadOrganization(id: org)
        XCTAssertEqual(o2.name, "Renamed"); XCTAssertEqual(o2.branding.look(.church).primaryColor, "#123456")
        do { try await demo.saveOrganization(id: org, name: "x", branding: BrandingSettings(object: ["youtube_channel_id": .string("bad")])); XCTFail("bad channel") } catch {}
    }

    func testDemoLibraryDeleteProtectionAndFolders() async throws {
        let demo = MockService()
        let org = MockService.churchId
        let kids = try await demo.listMedia(organizationId: org, module: .kids, kinds: [])
        let usage = try await demo.mediaUsage(organizationId: org, module: .kids)
        let used = try XCTUnwrap(kids.first { usage[$0.id] != nil })
        do { try await demo.deleteMedia(used, organizationId: org); XCTFail("must be refused") }
        catch { XCTAssertTrue((error as? ChurchError)?.message.contains("is used in:") == true) }
        let free = try XCTUnwrap(kids.first { usage[$0.id] == nil })
        try await demo.renameMedia(id: free.id, organizationId: org, title: "Renamed clip")
        let folder = try await demo.createFolder(organizationId: org, module: .kids, parent: nil, siteId: nil, name: "New folder")
        do { _ = try await demo.createFolder(organizationId: org, module: .kids, parent: nil, siteId: nil, name: "new FOLDER"); XCTFail("duplicate name") }
        catch { XCTAssertEqual((error as? ChurchError)?.message, "A folder with that name already exists here.") }
        try await demo.moveMedia(ids: [free.id], organizationId: org, module: .kids, to: folder.id)
        var lib = try await demo.listMedia(organizationId: org, module: .kids, kinds: [])
        XCTAssertEqual(lib.first { $0.id == free.id }?.folderId, folder.id); XCTAssertEqual(lib.first { $0.id == free.id }?.title, "Renamed clip")
        let sub = try await demo.createFolder(organizationId: org, module: .kids, parent: folder.id, siteId: nil, name: "Sub")
        do { try await demo.moveFolder(id: folder.id, organizationId: org, to: sub.id); XCTFail("cycle") } catch {}
        try await demo.deleteFolder(id: folder.id, organizationId: org)       // contents move up, nothing is deleted
        lib = try await demo.listMedia(organizationId: org, module: .kids, kinds: [])
        XCTAssertNil(lib.first { $0.id == free.id }?.folderId)
        let folders = try await demo.mediaFolders(organizationId: org, module: .kids)
        XCTAssertNil(folders.first { $0.id == sub.id }?.parentId)
        try await demo.deleteMedia(free, organizationId: org)
        let finalLib = try await demo.listMedia(organizationId: org, module: .kids, kinds: [])
        XCTAssertNil(finalLib.first { $0.id == free.id })
    }

    func testDemoSongs() async throws {
        let demo = MockService()
        let org = MockService.churchId
        let parsed = SongParsers.parseChordPro("{title: Test Song}\n{soc}\nLine A\n{eoc}")
        try await demo.insertSongs([SongDraft(parsed: parsed, source: .file)], organizationId: org)
        var songs = try await demo.listSongs(organizationId: org)
        let added = try XCTUnwrap(songs.first { $0.title == "Test Song" })
        XCTAssertEqual(added.source, "file"); XCTAssertEqual(added.sections.first?.label, "Chorus")
        var d = SongDraft(added); d.title = "Test Song 2"; d.linesPerSlide = 1
        let saved = try await demo.saveSong(d, organizationId: org)
        XCTAssertEqual(saved.id, added.id); XCTAssertEqual(saved.title, "Test Song 2")
        do { _ = try await demo.saveSong(SongDraft(title: ""), organizationId: org); XCTFail("needs title") } catch {}
        try await demo.deleteSong(id: added.id, organizationId: org)
        songs = try await demo.listSongs(organizationId: org)
        XCTAssertNil(songs.first { $0.id == added.id })
        // a song used by a playlist cannot be deleted
        let used = try await demo.songUsage(organizationId: org)
        let usedId = try XCTUnwrap(used.keys.first)
        do { try await demo.deleteSong(id: usedId, organizationId: org); XCTFail("must be refused") }
        catch { XCTAssertTrue((error as? ChurchError)?.message.contains("is used in:") == true) }
    }
}
