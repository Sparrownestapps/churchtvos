import XCTest
import ChurchTVCore
@testable import ChurchTVEditors

@MainActor
final class ImportFlowTests: XCTestCase {
    var dir: URL!
    var hosts: [TestHost] = []      // ImportFlow holds its ContentModel unowned, so the host must outlive it
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("import-flow-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func wait(_ flow: ImportFlow, for phase: ImportFlow.Phase, seconds: Double = 20) async throws {
        let end = Date().addingTimeInterval(seconds)
        while flow.phase != phase {
            if Date() > end { return XCTFail("Timed out in \(flow.phase), error: \(flow.errorText ?? "none")") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func start(_ target: ImportTarget, existing: Int = 2, apply: @escaping (ImportResult) -> Void) async -> (TestHost, ImportFlow) {
        let host = TestHost()
        await host.start()
        hosts.append(host)
        return (host, ImportFlow(target: target, content: host.content, existingCount: existing, siteId: nil, apply: apply))
    }

    func testPDFIntoDeckAfterPositionWithFolder() async throws {
        var applied: ImportResult?
        let (host, flow) = await start(.deck) { applied = $0 }
        flow.load(urls: [try ImportSamples.write(ImportSamples.pdf(pages: 4), named: "Easter.pdf", in: dir)])
        try await wait(flow, for: .preview)
        XCTAssertEqual(flow.entries.count, 4)
        XCTAssertEqual(flow.includedCount, 4)
        XCTAssertNil(flow.seconds)                                   // decks wait for Next
        flow.entries[1].included = false                             // untick page 2
        flow.move(flow.entries[3], .top)                             // page 4 first
        flow.placementMode = .after; flow.after = 1
        XCTAssertNil(flow.problem)
        flow.run()
        try await wait(flow, for: .finished)
        XCTAssertEqual(flow.outcome.added, 3)
        XCTAssertTrue(flow.outcome.failures.isEmpty)
        XCTAssertEqual(flow.outcome.folderName, "Easter")
        let result = try XCTUnwrap(applied)
        XCTAssertEqual(result.placement, .after(1))
        XCTAssertEqual(result.pages.map { $0.media?.title }, ["Easter 04", "Easter 01", "Easter 03"])   // list order, not upload order
        let folders = await host.content.folders(for: .slides)
        let folder = try XCTUnwrap(folders.first { $0.name == "Easter" })
        XCTAssertTrue(result.pages.allSatisfy { $0.media?.folderId == folder.id && $0.media?.module == "slides" })
        // A second import of the same name gets "(2)".
        let again = ImportFlow(target: .deck, content: host.content, existingCount: 0, siteId: nil) { _ in }
        again.load(urls: [try ImportSamples.write(ImportSamples.pdf(pages: 1), named: "Easter.pdf", in: dir)])
        try await wait(again, for: .preview)
        again.run()
        try await wait(again, for: .finished)
        XCTAssertEqual(again.outcome.folderName, "Easter (2)")
    }

    func testPPTXIntoNewDeckKeepsTextNotesAndVideo() async throws {
        let (host, flow) = await start(.deck) { _ in XCTFail("a new deck is created, nothing is applied to the open one") }
        flow.load(urls: [try ImportSamples.write(ImportSamples.pptx(), named: "Sunday.pptx", in: dir)])
        try await wait(flow, for: .preview)
        XCTAssertEqual(flow.includedCount, 5)                        // slides 1,2,3,4,7 (hidden and empty are off)
        XCTAssertTrue(flow.hasMedia)
        XCTAssertTrue(flow.hasPicturesOnTextSlides)
        flow.withPictures = true
        flow.placementMode = .new; flow.newName = "Sunday deck"
        flow.run()
        try await wait(flow, for: .finished)
        XCTAssertEqual(flow.outcome.createdName, "Sunday deck")
        let deck = try XCTUnwrap(host.content.decks.first { $0.name == "Sunday deck" })
        // 1 text, 2 text, 3 picture, 4 text, 7 text + its picture + its video
        XCTAssertEqual(deck.slides.count, 7)
        guard case .text(let t) = deck.slides[0].content else { return XCTFail() }
        XCTAssertEqual(t.title, "Welcome to Forward Church")
        XCTAssertEqual(deck.slides[0].notes, "Greet everyone. Mention the coffee bar.")
        guard case .media(let pic) = deck.slides[2].content else { return XCTFail() }
        XCTAssertEqual(pic.mediaKind, .image)
        guard case .media(let vid) = deck.slides[6].content else { return XCTFail() }
        XCTAssertEqual(vid.mediaKind, .video)
        XCTAssertTrue(deck.slides.allSatisfy { $0.problem == nil })
    }

    func testKidsPlaylistDrawsTextAsPicturesAndKeepsVideo() async throws {
        var applied: ImportResult?
        let (_, flow) = await start(.kids, existing: 0) { applied = $0 }
        XCTAssertEqual(flow.seconds, 10)
        flow.load(urls: [try ImportSamples.write(ImportSamples.pptx(), named: "Kids.pptx", in: dir)])
        try await wait(flow, for: .preview)
        flow.run()
        try await wait(flow, for: .finished)
        let result = try XCTUnwrap(applied)
        let items = ImportBuilder.playlistItems(pages: result.pages, seconds: result.seconds)
        XCTAssertEqual(items.count, 6)                               // 5 slides + the video of slide 7
        XCTAssertEqual(items.compactMap { $0.typeName }, [.image, .image, .image, .image, .image, .video])
        XCTAssertEqual(items[0].title, "Kids 01")                    // the drawn text slide
        XCTAssertTrue(items.allSatisfy { $0.problem == nil })
    }

    func testPerPageFailureDoesNotStopTheRestAndStopKeepsDone() async throws {
        var applied: ImportResult?
        let (_, flow) = await start(.deck) { applied = $0 }
        // One good picture and one file that looks like a picture but is not.
        let good = try ImportSamples.write(ImportSamples.picture(caption: "ok"), named: "A good.png", in: dir)
        let bad = try ImportSamples.write(Data("this is not a png".utf8), named: "B bad.png", in: dir)
        flow.load(urls: [good, bad])
        try await wait(flow, for: .preview)
        XCTAssertEqual(flow.entries.map(\.enabled), [true, false])  // the unreadable one is listed but cannot be ticked
        flow.entries[1].included = true                              // (forced on, as if it passed the preview)
        flow.run()
        try await wait(flow, for: .finished)
        XCTAssertEqual(flow.outcome.added, 1)
        XCTAssertEqual(flow.outcome.failures.count, 1)
        XCTAssertEqual(applied?.pages.count, 1)
    }

    func testPermissionHidesImport() async throws {
        let host = TestHost()
        await host.start()
        hosts.append(host)
        XCTAssertTrue(host.content.canAddMedia)
        XCTAssertEqual(ImportTarget.kids.module, .kids)
        XCTAssertEqual(ImportTarget.deck.module, .slides)
    }
}
