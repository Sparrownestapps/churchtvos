import XCTest
@testable import ChurchTVCore

final class MockContentServiceTests: XCTestCase {
    private let org = MockService.churchId

    func testSampleContentIsComplete() async throws {
        let s = MockService()
        let kids = try await s.listPlaylists(kind: .kids, organizationId: org)
        let signage = try await s.listPlaylists(kind: .signage, organizationId: org)
        let decks = try await s.listDecks(organizationId: org)
        let themes = try await s.listThemes(organizationId: org)
        let songs = try await s.listSongs(organizationId: org)
        XCTAssertEqual(kids.count, 2); XCTAssertEqual(signage.count, 2); XCTAssertEqual(decks.count, 2); XCTAssertEqual(themes.count, 2); XCTAssertEqual(songs.count, 5)
        // every slide kind appears in the demo decks, every item type in the demo playlists
        let kinds = Set(decks.flatMap(\.slides).compactMap(\.kind))
        XCTAssertEqual(kinds, Set(DeckSlide.Kind.allCases))
        let types = Set((kids + signage).flatMap(\.items).compactMap(\.typeName))
        XCTAssertEqual(types, Set(PlaylistItem.TypeName.allCases))
        // every song and media reference in the demo content exists
        let songIds = Set(songs.map { $0.id.uuidString.lowercased() })
        let media = try await AppModule.allCases.asyncFlatMap { try await s.listMedia(organizationId: self.org, module: $0, kinds: []) }
        let mediaIds = Set(media.map { $0.id.uuidString.lowercased() })
        for d in decks { for sl in d.slides {
            if case .song(let x) = sl.content { XCTAssertTrue(songIds.contains(x.songId)) }
            if case .media(let x) = sl.content { XCTAssertTrue(mediaIds.contains(x.mediaId)) }
        } }
        // demo songs include arrangement and lines_per_slide cases
        XCTAssertTrue(songs.contains { $0.arrangement != nil }); XCTAssertTrue(songs.contains { $0.linesPerSlide > 0 })
        // media: all three kinds, folders with nesting
        XCTAssertEqual(Set(media.map(\.kind)), [.image, .video, .audio])
        let folders = try await s.mediaFolders(organizationId: org, module: .slides)
        XCTAssertTrue(folders.contains { $0.parentId != nil })
        let locations = try await s.listLocations(organizationId: org)
        XCTAssertTrue(locations.contains { $0.uses(.kids) } && locations.contains { $0.uses(.slides) })
        // kind filter and module scope
        let audio = try await s.listMedia(organizationId: org, module: .slides, kinds: [.audio])
        XCTAssertEqual(audio.count, 2); XCTAssertTrue(audio.allSatisfy { $0.kind == .audio && $0.module == "slides" })
    }

    func testPlaylistCrud() async throws {
        let s = MockService()
        var draft = PlaylistDraft(organizationId: org, siteId: nil, name: "  New list  ", items: [PlaylistItem.newCountdown()])
        let created = try await s.createPlaylist(kind: .kids, draft: draft)
        XCTAssertEqual(created.name, "New list"); XCTAssertEqual(created.id, draft.id)
        var all = try await s.listPlaylists(kind: .kids, organizationId: org)
        XCTAssertEqual(all.count, 3)
        // the signage table is separate
        let signageCount = try await s.listPlaylists(kind: .signage, organizationId: org).count
        XCTAssertEqual(signageCount, 2)
        draft = PlaylistDraft(created); draft.name = "Renamed"; draft.items.append(PlaylistItem.newImage())
        let updated = try await s.updatePlaylist(kind: .kids, draft: draft)
        XCTAssertEqual(updated.name, "Renamed"); XCTAssertEqual(updated.itemCount, 2)
        let copy = try await s.duplicatePlaylist(kind: .kids, playlist: updated)
        XCTAssertEqual(copy.name, "Renamed (copy)"); XCTAssertNotEqual(copy.id, updated.id); XCTAssertEqual(copy.items, updated.items)
        try await s.deletePlaylist(kind: .kids, id: copy.id, organizationId: org)
        try await s.deletePlaylist(kind: .kids, id: updated.id, organizationId: org)
        all = try await s.listPlaylists(kind: .kids, organizationId: org)
        XCTAssertEqual(all.count, 2)
        // updating something that is gone fails with a readable message
        do { _ = try await s.updatePlaylist(kind: .kids, draft: draft); XCTFail("should fail") } catch { XCTAssertTrue(error.localizedDescription.contains("Couldn't save")) }
        // server-style refusal for a playlist in a repeating schedule
        do { try await s.deletePlaylist(kind: .kids, id: MockService.braveList.id, organizationId: org); XCTFail("should be refused") }
        catch { XCTAssertTrue(error.localizedDescription.contains("repeating schedule")) }
        // new playlists show up in Play now
        _ = try await s.createPlaylist(kind: .kids, draft: PlaylistDraft(organizationId: org, name: "Fresh"))
        let play = try await s.playNowItems(organizationId: org, modules: [.kids])
        XCTAssertTrue(play.contains { $0.name == "Fresh" })
    }

    func testDeckAndThemeCrud() async throws {
        let s = MockService()
        var deck = DeckDraft(organizationId: org, name: "My deck", slides: [DeckSlide.new(.blank, existing: [])], loops: true)
        let created = try await s.createDeck(draft: deck)
        XCTAssertEqual(created.slideCount, 1); XCTAssertTrue(created.loops)
        deck = DeckDraft(created); deck.slides.append(DeckSlide.new(.countdown, existing: deck.slides)); deck.themeId = nil
        let updated = try await s.updateDeck(draft: deck)
        XCTAssertEqual(updated.slideCount, 2)
        let copy = try await s.duplicateDeck(deck: updated)
        XCTAssertEqual(copy.name, "My deck (copy)")
        try await s.deleteDeck(id: copy.id, organizationId: org)
        let decksAfter = try await s.listDecks(organizationId: org)
        XCTAssertEqual(decksAfter.count, 3)
        do { try await s.deleteDeck(id: MockService.sundayDeck.id, organizationId: org); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("repeating schedule")) }

        // themes: unique names, duplicate gets a free name, deleting clears theme_id on decks
        let t = try await s.createTheme(organizationId: org, name: "Mine", config: .standard)
        do { _ = try await s.createTheme(organizationId: org, name: "mine", config: .standard); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("already exists")) }
        let names = try await s.listThemes(organizationId: org).map(\.name)
        let dup = try await s.duplicateTheme(t, existingNames: names)
        XCTAssertEqual(dup.name, "Mine (copy)")
        let dup2 = try await s.duplicateTheme(t, existingNames: names + [dup.name])
        XCTAssertEqual(dup2.name, "Mine (copy) 2")
        var edited = t; edited.config.margin = 12
        let saved = try await s.updateTheme(edited)
        XCTAssertEqual(saved.config.margin, 12)
        var d2 = DeckDraft(updated); d2.themeId = t.id
        _ = try await s.updateDeck(draft: d2)
        try await s.deleteTheme(id: t.id, organizationId: org)
        let decks = try await s.listDecks(organizationId: org)
        XCTAssertNil(decks.first { $0.id == updated.id }?.themeId)
    }

    func testUploadReturnsLibraryRow() async throws {
        let s = MockService()
        let req = MediaUploadRequest(organizationId: org, module: .kids, folderId: nil, fileURL: URL(fileURLWithPath: "/tmp/x.jpg"), filename: "x.jpg", title: "My photo", kind: .image, sizeBytes: 10, contentType: "image/jpeg")
        let item = try await s.uploadMediaItem(req) { _ in }
        XCTAssertEqual(item?.title, "My photo")
        let kids = try await s.listMedia(organizationId: org, module: .kids, kinds: [.image])
        XCTAssertTrue(kids.contains { $0.title == "My photo" })
    }

    func testNamingAndErrors() {
        XCTAssertEqual(ContentNaming.uniqueName("A", existing: ["a", "A 2"]), "A 3")
        XCTAssertEqual(ContentNaming.uniqueName("B", existing: []), "B")
        XCTAssertEqual(ContentErrors.friendly("duplicate key value violates unique constraint \"slide_themes_organization_id_name_key\""), "A theme with that name already exists. Choose another name.")
        XCTAssertEqual(ContentErrors.friendly("new row violates row-level security policy for table \"decks\""), "You do not have permission to change this. Ask a church admin.")
        let server = "\"Song\" is used in: Week 3. Remove it from those playlists first."
        XCTAssertEqual(ContentErrors.friendly(server), server, "server messages pass through unchanged")
    }
}

extension Sequence {
    func asyncFlatMap<T>(_ f: (Element) async throws -> [T]) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out += try await f(e) }
        return out
    }
}
