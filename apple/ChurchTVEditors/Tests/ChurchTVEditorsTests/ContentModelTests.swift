import XCTest
import ChurchTVCore
@testable import ChurchTVEditors

@MainActor
final class ContentModelHostTests: XCTestCase {
    func testDeletingNotifiesTheHostAndHostWithoutPlayNowHidesIt() async throws {
        let host = TestHost()
        await host.start()
        let content = host.content
        XCTAssertFalse(content.canPlayNow, "a host without Play now support never offers it")
        XCTAssertFalse(content.canControl)
        XCTAssertTrue(content.canAddMedia, "the demo church is an editor with live modules")
        await content.load(.slides)
        var draft = content.newDeckDraft(name: "Throwaway")
        draft.slides = [DeckSlide.new(.blank, existing: [])]
        let saved = try await content.save(draft)
        try await content.delete(saved)
        XCTAssertEqual(host.reloadedPlayNow, 1)
    }

    func testResetForgetsLoadedLists() async {
        let host = TestHost()
        await host.start()
        await host.content.load(.kids)
        XCTAssertFalse(host.content.kids.isEmpty)
        host.content.reset()
        XCTAssertTrue(host.content.kids.isEmpty)
    }
}
