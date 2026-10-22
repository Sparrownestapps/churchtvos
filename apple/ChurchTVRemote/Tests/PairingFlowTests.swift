import XCTest
import ChurchTVCore
@testable import ChurchTVRemote

@MainActor
final class PairingFlowTests: XCTestCase {
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
}
