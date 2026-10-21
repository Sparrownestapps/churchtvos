import XCTest
import ChurchTVCore
@testable import ChurchTVEditors

/// EXPERIMENTAL NDI source in the Kids playlist and Slides deck editors (NDI-CONTRACT.md).
@MainActor
final class NdiEditingTests: XCTestCase {
    private let org = UUID()
    private let ndi = NdiSettings(title: "Main camera", source: "STUDIO-PC (Camera 1)")

    func testNewNdiItemAndSlideHaveContractDefaults() {
        guard case .ndi(let item) = PlaylistEditing.newItem(.ndi, kind: .kids).content else { return XCTFail() }
        XCTAssertEqual(item.ndi, NdiSettings())
        XCTAssertNotNil(PlaylistEditing.newItem(.ndi, kind: .kids).problem, "a source name is required")
        var slides: [DeckSlide] = []
        DeckEditing.add(.ndi, to: &slides, after: nil)
        XCTAssertEqual(slides[0].ndiSettings, NdiSettings())
        XCTAssertNotNil(slides[0].problem)
        XCTAssertFalse(DeckEditing.supportsBackground(slides[0]))
    }

    func testRowsAndLabels() {
        let item = PlaylistItem(.ndi(NdiItem(ndi: ndi)))
        let t = PlaylistEditing.rowText(item, songs: [:], kind: .kids)
        XCTAssertEqual(t.title, "Main camera"); XCTAssertTrue(t.detail.contains("NDI"))
        XCTAssertEqual(PlaylistEditing.knownSeconds(PlaylistItem(.ndi(NdiItem(ndi: NdiSettings(source: "A (B)", seconds: 90))))), 90)
        XCTAssertNil(PlaylistEditing.knownSeconds(item))
        let slide = DeckSlide(id: "s_1", content: .ndi(NdiSettings(source: "STUDIO-PC (Camera 1)")))
        XCTAssertEqual(DeckEditing.label(slide, songs: [:]) { _ in nil }, "STUDIO-PC (Camera 1)")
        XCTAssertEqual(PlaylistEditorLabels.menuLabel(.ndi, kind: .kids), "NDI source (experimental)")
    }

    func testDuplicateIsRefusedWithoutTheFlag() {
        var items = [PlaylistItem(.ndi(NdiItem(ndi: ndi)))]
        PlaylistEditing.duplicate(at: 0, in: &items, allowNdi: false)
        XCTAssertEqual(items.count, 1)
        PlaylistEditing.duplicate(at: 0, in: &items, allowNdi: true)
        XCTAssertEqual(items.count, 2)
        var slides = [DeckSlide(id: "s_1", content: .ndi(ndi))]
        XCTAssertNil(DeckEditing.duplicate(0, in: &slides, allowNdi: false))
        XCTAssertNotNil(DeckEditing.duplicate(0, in: &slides, allowNdi: true))
        XCTAssertEqual(slides.count, 2)
    }

    func testEditingKeepsUnknownKeysAndFlagReachesEditors() async throws {
        let host = TestHost()
        await host.start()
        XCTAssertEqual(host.content.ndiEnabled, MockService.demoNdiEnabled)
        // an item with a key this app does not know survives an edit of its settings
        let json = ##"{"type":"ndi","title":"Cam","source":"A (B)","audio":false,"fit":"fit","fallback":"skip","max_wait_seconds":15,"seconds":null,"future":{"x":1}}"##
        var item = try ContentJSON.decoder().decode(PlaylistItem.self, from: Data(json.utf8))
        guard case .ndi(var n) = item.content else { return XCTFail() }
        n.ndi.fit = .fill; n.ndi.fallback = .message; n.ndi.fallbackText = "Back soon"
        item.content = .ndi(n)
        XCTAssertEqual(item.object["future"], .object(["x": .number(1)]))
        XCTAssertEqual(item.object["fit"], .string("fill")); XCTAssertEqual(item.object["fallback_text"], .string("Back soon"))
    }

    func testSavingNdiThroughTheEditorModelObeysTheFlag() async throws {
        let host = TestHost()
        await host.start()
        let draft = PlaylistDraft(organizationId: MockService.churchId, name: "Cams", items: [PlaylistItem(.ndi(NdiItem(ndi: ndi)))])
        if host.content.ndiEnabled {
            let saved = try await host.content.save(draft, kind: .kids)
            XCTAssertEqual(saved.items.ndiEntries, [ndi])
        } else {
            do { _ = try await host.content.save(draft, kind: .kids); XCTFail("the server refuses NDI without the flag") }
            catch { XCTAssertTrue(Formatting.message(for: error).contains("not enabled for this church")) }
        }
    }
}
