import XCTest
import ChurchTVCore
@testable import ChurchTVRemote

@MainActor
final class PairingFlowTests: XCTestCase {
    override func setUp() async throws { await MockService.resetDemoPairing() }

    func testDemoPairingAddsScreen() async throws {
        let model = AppModel(service: MockService())
        await model.startDemo()
        XCTAssertTrue(model.canPair)
        let flow = PairingFlow()
        await flow.load(model: model)
        XCTAssertFalse(flow.locations.isEmpty)
        flow.locationId = flow.locations.first?.id
        XCTAssertFalse(flow.canSubmit)
        XCTAssertTrue(flow.handleScan("https://app.churchtvos.com/pair?code=dem723"))
        XCTAssertEqual(flow.code, "DEM 723")
        XCTAssertTrue(flow.canSubmit)
        let before = model.screens.count
        await flow.submit(model: model)
        XCTAssertNil(flow.error)
        XCTAssertNotNil(flow.pairedName)
        XCTAssertEqual(model.screens.count, before + 1)
    }

    func testBadAndWrongCodes() async throws {
        let model = AppModel(service: MockService())
        await model.startDemo()
        let flow = PairingFlow()
        await flow.load(model: model)
        flow.locationId = flow.locations.first?.id
        XCTAssertFalse(flow.handleScan("https://example.com/other"))
        XCTAssertNotNil(flow.scanHint)
        flow.setTyped("zzz 999")
        await flow.submit(model: model)
        XCTAssertTrue(flow.error?.hasPrefix("No TV is showing that code") ?? false)
        XCTAssertNil(flow.pairedName)
        flow.setTyped("zzz 0o9")           // not a possible code
        XCTAssertFalse(flow.canSubmit)
    }

    func testNewRoomInNewSiteThenPair() async throws {
        let model = AppModel(service: MockService())
        await model.startDemo()
        let flow = PairingFlow()
        await flow.load(model: model)
        let rooms = flow.locations.count
        flow.pick(RoomRules.newRoomTag)
        flow.beginNewRoom(church: model.church!)
        XCTAssertTrue(flow.creatingRoom)
        XCTAssertEqual(flow.draft.modules, Set(model.church!.modules.map(\.rawValue)))
        flow.setTyped("DEM 723")
        XCTAssertFalse(flow.canSubmit)               // no room name yet
        flow.draft.name = "  Nursery "
        flow.pickSite(RoomRules.newSiteTag)
        XCTAssertFalse(flow.canSubmit)               // no site name yet
        flow.draft.newSiteName = "East Campus"
        XCTAssertTrue(flow.canSubmit)
        await flow.submit(model: model)
        XCTAssertNil(flow.error)
        XCTAssertNotNil(flow.pairedName)
        XCTAssertEqual(flow.locations.count, rooms + 1)
        XCTAssertTrue(flow.sites.contains { $0.name == "East Campus" })
        XCTAssertEqual(flow.pairedLocation, "Nursery · East Campus")
        let locs = try await model.service.listLocations(organizationId: model.church!.id)
        XCTAssertTrue(locs.contains { $0.name == "Nursery" })
    }

    func testDuplicateRoomNameBlocked() async throws {
        let model = AppModel(service: MockService())
        await model.startDemo()
        let flow = PairingFlow()
        await flow.load(model: model)
        let existing = flow.locations[0]
        flow.beginNewRoom(church: model.church!)
        flow.draft.siteId = existing.siteId; flow.draft.creatingSite = false
        flow.draft.name = existing.name.uppercased()
        XCTAssertNotNil(flow.roomProblem)
    }

    func testFailedClaimKeepsRoomAndRetryDoesNotDuplicate() async throws {
        let model = AppModel(service: MockService())
        await model.startDemo()
        let flow = PairingFlow()
        await flow.load(model: model)
        flow.beginNewRoom(church: model.church!)
        flow.draft.siteId = flow.sites.first?.id; flow.draft.creatingSite = false
        flow.draft.name = "Cafe"
        flow.setTyped("zzz 999")                     // no TV shows this code
        await flow.submit(model: model)
        XCTAssertNil(flow.pairedName)
        XCTAssertTrue(flow.error?.contains("was created") ?? false)
        XCTAssertFalse(flow.creatingRoom)
        let cafe = flow.locations.first { $0.name == "Cafe" }
        XCTAssertNotNil(cafe)
        XCTAssertEqual(flow.locationId, cafe?.id)    // selected
        flow.setTyped("DEM 723")
        await flow.submit(model: model)              // retry claims into the existing room
        XCTAssertNil(flow.error)
        XCTAssertNotNil(flow.pairedName)
        XCTAssertEqual(flow.locations.filter { $0.name == "Cafe" }.count, 1)
        let locs = try await model.service.listLocations(organizationId: model.church!.id)
        XCTAssertEqual(locs.filter { $0.name == "Cafe" }.count, 1)
    }
}
