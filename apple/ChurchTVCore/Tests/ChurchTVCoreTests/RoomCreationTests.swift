import XCTest
@testable import ChurchTVCore

final class RoomCreationTests: XCTestCase {
    let org = UUID()
    let s1 = Site(id: UUID(), name: "Downtown", timezone: "America/Toronto")
    let s2 = Site(id: UUID(), name: "East", timezone: "America/Vancouver")

    func sampleLocations() -> [Location] { [Location(id: UUID(), name: "Lobby", siteId: s1.id, modules: ["kids"])] }

    func testValidation() {
        var d = NewRoomDraft(name: "  Nursery ", siteId: s1.id, modules: ["kids"])
        XCTAssertNil(RoomRules.problem(d, role: .admin, sites: [s1], locations: sampleLocations()))
        XCTAssertNotNil(RoomRules.problem(d, role: .editor, sites: [s1], locations: []))
        XCTAssertNotNil(RoomRules.problem(d, role: .operator, sites: [s1], locations: []))
        d.name = "   "; XCTAssertNotNil(RoomRules.problem(d, role: .owner, sites: [s1], locations: []))
        d.name = " lobby "; XCTAssertEqual(RoomRules.problem(d, role: .owner, sites: [s1], locations: sampleLocations()), "A room named \"lobby\" already exists in this site.")
        d.name = "Nursery"; d.modules = []; XCTAssertNotNil(RoomRules.problem(d, role: .owner, sites: [s1], locations: []))
        d.modules = ["bogus"]; XCTAssertNotNil(RoomRules.problem(d, role: .owner, sites: [s1], locations: []))
        d.modules = ["slides"]; d.siteId = nil; XCTAssertNotNil(RoomRules.problem(d, role: .owner, sites: [s1], locations: []))
    }

    func testSameNameInOtherSiteIsFine() {
        let d = NewRoomDraft(name: "Lobby", siteId: s2.id, modules: ["kids"])
        XCTAssertNil(RoomRules.problem(d, role: .owner, sites: [s1, s2], locations: sampleLocations()))
    }

    func testNewSiteValidation() {
        var d = NewRoomDraft(name: "Lobby", creatingSite: true, newSiteName: "East", newSiteTimeZone: "America/Toronto", modules: ["kids"])
        XCTAssertNil(RoomRules.problem(d, role: .admin, sites: [s1], locations: sampleLocations()))   // same room name is fine in a new site
        d.newSiteName = " downtown "; XCTAssertNotNil(RoomRules.problem(d, role: .admin, sites: [s1], locations: []))
        d.newSiteName = ""; XCTAssertNotNil(RoomRules.problem(d, role: .admin, sites: [s1], locations: []))
        d.newSiteName = "East"; d.newSiteTimeZone = "Mars/Base"; XCTAssertNotNil(RoomRules.problem(d, role: .admin, sites: [s1], locations: []))
    }

    func testDefaults() {
        XCTAssertEqual(RoomRules.defaultModules(church: [.kids, .slides]), ["kids", "slides"])
        XCTAssertEqual(RoomRules.defaultTimeZone(sites: [Site(id: UUID(), name: "A", timezone: "Nope"), s1], device: "Europe/London"), "America/Toronto")
        XCTAssertEqual(RoomRules.defaultTimeZone(sites: [], device: "Europe/London"), "Europe/London")
    }

    func testPayloads() throws {
        let sid = UUID()
        let loc = RoomRules.locationRow(organizationId: org, siteId: sid, name: "  Youth Loft ", modules: ["slides", "kids", "junk"])
        XCTAssertEqual(loc.name, "Youth Loft"); XCTAssertEqual(loc.modules, ["kids", "slides"])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loc)) as! [String: Any]
        XCTAssertEqual(json["organization_id"] as? String, org.uuidString.lowercased())
        XCTAssertEqual(json["site_id"] as? String, sid.uuidString.lowercased())
        XCTAssertEqual(json["modules"] as? [String], ["kids", "slides"])
        let site = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RoomRules.siteRow(organizationId: org, name: " East ", timezone: " America/Toronto "))) as! [String: Any]
        XCTAssertEqual(site["name"] as? String, "East"); XCTAssertEqual(site["timezone"] as? String, "America/Toronto")
        XCTAssertEqual(Set(site.keys), ["organization_id", "name", "timezone"])
    }

    // MARK: Orchestration

    actor Recorder { var calls: [String] = []; func add(_ s: String) { calls.append(s) } }
    struct Fake: OperationsService {
        let rec: Recorder; var failSite = false; var failLocation = false; var failClaim = false
        func createSite(organizationId: UUID, name: String, timezone: String) async throws -> Site {
            await rec.add("site"); if failSite { throw ChurchError("boom") }
            return Site(id: UUID(), name: name, timezone: timezone)
        }
        func createLocation(organizationId: UUID, siteId: UUID, name: String, modules: [String]) async throws -> Location {
            await rec.add("location"); if failLocation { throw ChurchError("duplicate key value violates unique constraint \"locations_site_id_name_key\"") }
            return Location(id: UUID(), name: name, siteId: siteId, modules: modules)
        }
        func claimScreen(code: String, locationId: UUID, name: String?) async throws {
            await rec.add("claim"); if failClaim { throw ChurchError("No TV is showing code \(code)") }
        }
    }

    func testOrderSiteLocationClaim() async {
        let rec = Recorder()
        let d = NewRoomDraft(name: "Lobby", creatingSite: true, newSiteName: "East", newSiteTimeZone: "America/Toronto", modules: ["kids"])
        let r = await RoomPairing.run(ops: Fake(rec: rec), organizationId: org, code: "ABC123", tvName: nil, draft: d, existingSite: nil)
        let calls = await rec.calls
        XCTAssertEqual(calls, ["site", "location", "claim"])
        XCTAssertTrue(r.paired); XCTAssertNil(r.message); XCTAssertEqual(r.location?.siteId, r.site?.id)
    }

    func testExistingSiteSkipsSite() async {
        let rec = Recorder()
        let r = await RoomPairing.run(ops: Fake(rec: rec), organizationId: org, code: "ABC123", tvName: "TV", draft: NewRoomDraft(name: "Lobby", siteId: s1.id, modules: ["kids"]), existingSite: s1)
        let calls = await rec.calls
        XCTAssertEqual(calls, ["location", "claim"]); XCTAssertTrue(r.paired); XCTAssertEqual(r.location?.siteId, s1.id)
    }

    func testClaimFailureKeepsRoom() async {
        let rec = Recorder()
        let r = await RoomPairing.run(ops: Fake(rec: rec, failClaim: true), organizationId: org, code: "ABC123", tvName: nil, draft: NewRoomDraft(name: "Lobby", siteId: s1.id, modules: ["kids"]), existingSite: s1)
        XCTAssertFalse(r.paired); XCTAssertNotNil(r.location); XCTAssertTrue(r.message?.contains("was created") ?? false)
    }

    func testSiteFailureStopsEarly() async {
        let rec = Recorder()
        let d = NewRoomDraft(name: "Lobby", creatingSite: true, newSiteName: "East", modules: ["kids"])
        let r = await RoomPairing.run(ops: Fake(rec: rec, failSite: true), organizationId: org, code: "ABC123", tvName: nil, draft: d, existingSite: nil)
        let calls = await rec.calls
        XCTAssertEqual(calls, ["site"]); XCTAssertNil(r.location); XCTAssertNotNil(r.message)
    }

    func testLocationFailureKeepsNewSite() async {
        let rec = Recorder()
        let d = NewRoomDraft(name: "Lobby", creatingSite: true, newSiteName: "East", modules: ["kids"])
        let r = await RoomPairing.run(ops: Fake(rec: rec, failLocation: true), organizationId: org, code: "ABC123", tvName: nil, draft: d, existingSite: nil)
        let calls = await rec.calls
        XCTAssertEqual(calls, ["site", "location"]); XCTAssertNotNil(r.site); XCTAssertNil(r.location)
        XCTAssertTrue(r.message?.contains("already exists") ?? false)
    }

    func testDemoCreateAndPair() async throws {
        let svc = MockService()
        let site = try await svc.createSite(organizationId: MockService.churchId, name: "East Campus", timezone: "America/Toronto")
        let loc = try await svc.createLocation(organizationId: MockService.churchId, siteId: site.id, name: "Cafe", modules: ["signage"])
        let sites = try await svc.listSites(organizationId: MockService.churchId)
        let locs = try await svc.listLocations(organizationId: MockService.churchId)
        XCTAssertTrue(sites.contains(site)); XCTAssertTrue(locs.contains(loc))
        do { _ = try await svc.createLocation(organizationId: MockService.churchId, siteId: site.id, name: "cafe", modules: ["signage"]); XCTFail("duplicate") } catch {}
        try await svc.claimScreen(code: "DEM 723", locationId: loc.id, name: "Cafe TV")
    }
}
