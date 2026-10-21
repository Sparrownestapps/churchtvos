import XCTest
import ChurchTVCore
@testable import ChurchTVRemote

@MainActor
final class CreateSectionTests: XCTestCase {
    private func church(_ role: Role, modules: [AppModule], siteIds: [UUID]? = nil) -> ChurchAccess {
        ChurchAccess(organization: Organization(id: MockService.churchId, name: "Test"), role: role, modules: modules, siteIds: siteIds)
    }

    func testCreateSectionVisibilityFollowsRoleAndModules() async {
        let model = AppModel(service: MockService())
        await model.startDemo()
        XCTAssertTrue(model.canCreate, "the demo church counts as an editor")
        await model.choose(church(.editor, modules: [.signage]))
        XCTAssertTrue(model.canCreate)
        XCTAssertEqual(model.church?.editableModules, [.signage])
        await model.choose(church(.operator, modules: AppModule.allCases))
        XCTAssertFalse(model.canCreate, "operators never see Create")
        await model.choose(church(.owner, modules: []))
        XCTAssertFalse(model.canCreate, "no live module, nothing to create")
    }

    func testContentModelSavesDuplicatesAndShowsServerRefusals() async throws {
        let model = AppModel(service: MockService())
        await model.startDemo()
        let content = model.content
        await content.load(.kids)
        XCTAssertEqual(content.kids.count, 2)

        var draft = content.newPlaylistDraft(name: "Week 5")
        draft.items = [PlaylistItem.newCountdown()]
        let saved = try await content.save(draft, kind: .kids)
        XCTAssertEqual(content.kids.count, 3)
        XCTAssertEqual(saved.name, "Week 5")

        // validation text is shown instead of a server round trip
        var bad = PlaylistDraft(saved)
        bad.items.append(PlaylistItem.newVideo())
        do { _ = try await content.save(bad, kind: .kids); XCTFail("should be refused") }
        catch { XCTAssertEqual(error.localizedDescription, "Item 2 needs a video chosen.") }

        try await content.duplicate(saved, kind: .kids)
        XCTAssertEqual(content.kids.count, 4)
        // the server's own refusal text reaches the caller unchanged
        let brave = try XCTUnwrap(content.kids.first { $0.id == MockService.braveList.id })
        do { try await content.delete(brave, kind: .kids); XCTFail("should be refused") }
        catch { XCTAssertTrue(error.localizedDescription.contains("repeating schedule")) }
        XCTAssertEqual(content.kids.count, 4)

        await content.load(.slides)
        let deck = try XCTUnwrap(content.decks.first { $0.name.hasPrefix("Christmas") })
        try await content.delete(deck)
        XCTAssertFalse(content.decks.contains { $0.id == deck.id })
        XCTAssertFalse(model.playNowItems.contains { $0.refId == deck.id }, "Play now follows deleted decks")
    }

    func testSiteChoices() async {
        let model = AppModel(service: MockService())
        await model.startDemo()
        await model.content.loadSupport()
        XCTAssertTrue(model.content.hasAllSites)
        XCTAssertNil(model.content.defaultSiteId)
        let sites = model.content.sites
        XCTAssertEqual(sites.count, 2)
        await model.choose(church(.editor, modules: [.kids], siteIds: [sites[1].id]))
        XCTAssertFalse(model.content.hasAllSites)
        XCTAssertEqual(model.content.selectableSites.map(\.id), [])   // sites reload after choosing a church
        await model.content.loadSupport()
        XCTAssertEqual(model.content.selectableSites.map(\.id), [sites[1].id])
        XCTAssertEqual(model.content.defaultSiteId, sites[1].id)
    }
}
