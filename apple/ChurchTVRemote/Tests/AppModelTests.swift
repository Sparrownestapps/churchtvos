import XCTest
import ChurchTVCore
@testable import ChurchTVRemote

@MainActor
final class AppModelTests: XCTestCase {
    func testDemoFlowReachesReadyAndMovesSlides() async throws {
        let model = AppModel(service: MockService())
        await model.startDemo()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.isDemo)
        XCTAssertEqual(model.screens.count, 4)
        let main = try XCTUnwrap(model.screens.first { $0.screen.displayName == "Main Auditorium" })
        let before = main.status?.slideIndex ?? 0
        let ok = await model.send(.next, to: main)
        XCTAssertTrue(ok)
        await model.refreshScreens()
        let after = model.screens.first { $0.id == main.id }?.status?.slideIndex
        XCTAssertEqual(after, before + 1)
    }
}
