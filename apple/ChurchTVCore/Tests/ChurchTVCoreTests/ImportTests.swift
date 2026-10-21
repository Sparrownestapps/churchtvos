import XCTest
import CoreGraphics
@testable import ChurchTVCore

final class ImportTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("import-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: Zip

    func testZipStoredRoundTrip() throws {
        let zip = try ZipArchive(data: ZipWriter.make([("a.txt", Data("hello".utf8)), ("dir/b.txt", Data("world".utf8))]))
        XCTAssertEqual(zip.entries.count, 2)
        XCTAssertEqual(String(data: try zip.data(named: "dir/b.txt")!, encoding: .utf8), "world")
        XCTAssertNil(try zip.data(named: "missing"))
    }

    func testZipInflatesRealDeflate() throws {
        // Made with python zipfile (ZIP_DEFLATED): "hello hello hello ..." x 40
        let b64 = "UEsDBBQAAAAIACxcVV0LKx+hCwAAAKgAAAAJAAAAaGVsbG8udHh0y0jNyclXyBj0JABQSwECFAMUAAAACAAsXFVdCysfoQsAAACoAAAACQAAAAAAAAAAAAAAgAEAAAAAaGVsbG8udHh0UEsFBgAAAAABAAEANwAAADIAAAAAAA=="
        let zip = try ZipArchive(data: Data(base64Encoded: b64)!)
        XCTAssertEqual(zip.entries.first?.method, 8)
        let d = try zip.data(named: "hello.txt")!
        XCTAssertEqual(String(data: d, encoding: .utf8), String(repeating: "hello ", count: 28))
    }

    func testZipRejectsGarbageAndLimits() throws {
        XCTAssertThrowsError(try ZipArchive(data: Data("not a zip at all, definitely not".utf8)))
        let zip = try ZipArchive(data: ZipWriter.make([("big.bin", Data(count: 5000))]))
        XCTAssertThrowsError(try zip.data(named: "big.bin", maxBytes: 100)) { XCTAssertEqual($0 as? ZipError, .tooLarge("big.bin")) }
    }

    func testZipTruncatedIsCorruptNotCrash() throws {
        var bytes = ZipWriter.make([("a.txt", Data("hello".utf8))])
        bytes.removeLast(10)
        XCTAssertThrowsError(try ZipArchive(data: bytes))
    }

    // MARK: PPTX

    func testPPTXReadsContractRules() throws {
        let pkg = try PPTXPackage(data: ImportSamples.pptx())
        XCTAssertEqual(pkg.slides.count, 7)
        XCTAssertEqual(pkg.aspect, 16.0 / 9.0, accuracy: 0.001)
        let s1 = pkg.slides[0]
        XCTAssertEqual(s1.title, "Welcome to Forward Church")
        XCTAssertEqual(s1.body, "Sunday 10:30 AM")          // footer placeholder skipped
        XCTAssertEqual(s1.notes, "Greet everyone. Mention the coffee bar.")
        let s2 = pkg.slides[1]
        XCTAssertEqual(s2.title, "This week at Forward")
        // Text boxes keep tree order (right box first in the file), one blank line between blocks, runs of blank paragraphs collapse.
        XCTAssertEqual(s2.body, "Kids check-in opens 10:00\nNursery to age 3\n\nParking team needs help\n\nSign up at the Welcome desk")
        let s3 = pkg.slides[2]
        XCTAssertEqual(s3.kind, .picture)
        XCTAssertEqual(s3.mainPicture?.path, "ppt/media/image1.png")
        XCTAssertEqual(s3.mainPicture?.area, 12_192_000 * 6_858_000)
        let s4 = pkg.slides[3]
        XCTAssertEqual(s4.title, "")                           // a lone text box is body text, not a title
        XCTAssertEqual(s4.body, "Offering: give online at forward.church")
        XCTAssertTrue(pkg.slides[4].hidden)
        XCTAssertEqual(pkg.slides[5].kind, .empty)
        let s7 = pkg.slides[6]
        XCTAssertEqual(s7.title, "Watch this")
        XCTAssertEqual(s7.body, "Then talk about it\n– Second level point")   // level 2 paragraphs start with an en dash
        XCTAssertEqual(s7.pictures.map(\.path), ["ppt/media/image1.png"])        // the video's poster frame is not a picture
        XCTAssertEqual(s7.media.count, 1)
        XCTAssertEqual(s7.media[0].path, "ppt/media/clip1.mp4")
        XCTAssertEqual(s7.media[0].kind, .video)
        XCTAssertTrue(s7.media[0].supported)
        XCTAssertEqual(s7.media[0].size, 2048)
    }

    func testFirstTextBoxBecomesTitleRule() throws {
        func shape(_ paras: [String], box: Bool = true) -> (paras: [String], isTextBox: Bool) { (paras, box) }
        // two text boxes, the first one a short single line -> title
        let xml = "<p:sld xmlns:a=\"a\" xmlns:p=\"p\"><p:cSld><p:spTree>"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"1\" name=\"a\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:txBody><a:p><a:r><a:t>Heading</a:t></a:r></a:p></p:txBody></p:sp>"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"b\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:txBody><a:p><a:r><a:t>Details here</a:t></a:r></a:p></p:txBody></p:sp>"
            + "</p:spTree></p:cSld></p:sld>"
        let parsed = PPTXPackage.parseSlide(XMLTreeParser.parse(Data(xml.utf8))!, rels: [:])
        XCTAssertEqual(parsed.title, "Heading")
        XCTAssertEqual(parsed.body, "Details here")
        let long = xml.replacingOccurrences(of: "Heading", with: String(repeating: "x", count: 81))
        XCTAssertEqual(PPTXPackage.parseSlide(XMLTreeParser.parse(Data(long.utf8))!, rels: [:]).title, "")
    }

    func testJoinParagraphsAndRelPaths() {
        XCTAssertEqual(PPTXPackage.joinParagraphs(["", "a", "", "", "b", ""]), "a\n\nb")
        XCTAssertEqual(PPTXPackage.resolve("ppt/slides", "../media/a.png"), "ppt/media/a.png")
        XCTAssertEqual(PPTXPackage.resolve("ppt/slides", "/ppt/media/b.png"), "ppt/media/b.png")
    }

    func testPPTXRejectsNonPowerPoint() {
        XCTAssertThrowsError(try PPTXPackage(data: ZipWriter.make([("word/document.xml", Data("<x/>".utf8))]))) { XCTAssertEqual($0 as? PPTXError, .notPowerPoint) }
        XCTAssertThrowsError(try PPTXPackage(data: Data(repeating: 7, count: 100))) { XCTAssertEqual($0 as? PPTXError, .notPowerPoint) }
    }

    func testSessionFromPPTXAndPlans() throws {
        let url = try ImportSamples.write(ImportSamples.pptx(), named: "Sunday Slides.pptx", in: dir)
        let s = try ImportSession.open(urls: [url])
        XCTAssertEqual(s.kind, .pptx)
        XCTAssertEqual(s.name, "Sunday Slides")
        XCTAssertEqual(s.entries.map(\.style), [.text, .text, .picture, .text, .text, .empty, .text])
        XCTAssertEqual(s.entries.map(\.included), [true, true, true, true, false, false, true])   // hidden and empty start unticked
        XCTAssertEqual(s.entries.map(\.enabled), [true, true, true, true, true, false, true])
        XCTAssertEqual(s.entries[0].title, "1. Welcome to Forward Church")
        XCTAssertTrue(s.entries[0].detail.contains("speaker notes"))
        XCTAssertEqual(s.mediaEntries.count, 1)
        XCTAssertEqual(s.mediaEntries[0].slideNumber, 7)
        XCTAssertTrue(s.mediaEntries[0].included)
        XCTAssertNotNil(s.thumbnail(for: s.entries[2]))
        XCTAssertNil(s.thumbnail(for: s.entries[0]))

        // Deck plan: text slide keeps text and notes, no upload.
        let deck = ImportPlanOptions(mode: .deck, withPictures: true, mediaOn: ["ppt/media/clip1.mp4"])
        let p1 = try s.plan(s.entries[0], options: deck)
        XCTAssertEqual(p1.count, 1)
        XCTAssertNil(p1[0].source)
        XCTAssertEqual(p1[0].text, ImportedText(title: "Welcome to Forward Church", body: "Sunday 10:30 AM"))
        XCTAssertEqual(p1[0].notes, "Greet everyone. Mention the coffee bar.")
        // Picture slide: file named "<base> <NN>.<ext>".
        let p3 = try s.plan(s.entries[2], options: deck)
        XCTAssertEqual(p3.map(\.fileName), ["Sunday Slides 03.png"])
        let f = try s.prepare(p3[0], directory: dir)
        XCTAssertEqual(f.contentType, "image/png"); XCTAssertEqual(f.title, "Sunday Slides 03"); XCTAssertEqual(f.kind, .image)
        // Slide 7: text, its picture (option), then the video, in that order.
        let p7 = try s.plan(s.entries[6], options: deck)
        XCTAssertEqual(p7.map(\.fileName), ["", "Sunday Slides 07 picture 1.png", "Sunday Slides 07 clip1.mp4"])
        XCTAssertEqual(p7.map(\.isVideo), [false, false, true])
        let video = try s.prepare(p7[2], directory: dir)
        XCTAssertEqual(video.contentType, "video/mp4"); XCTAssertEqual(video.kind, .video); XCTAssertEqual(video.size, 2048)
        XCTAssertEqual(try s.plan(s.entries[6], options: ImportPlanOptions(mode: .deck)).count, 1)       // no pictures, video not ticked

        // Kids plan: text becomes a drawn picture, notes are dropped.
        let kids = ImportPlanOptions(mode: .kidsPlaylist, withPictures: true, mediaOn: [])
        let k1 = try s.plan(s.entries[0], options: kids)
        XCTAssertEqual(k1.count, 1)
        XCTAssertEqual(k1[0].fileName, "Sunday Slides 01.jpg")
        XCTAssertEqual(k1[0].notes, "")
        let drawn = try s.prepare(k1[0], directory: dir, backgroundHex: "#1f3a5f")
        XCTAssertEqual(drawn.contentType, "image/jpeg")
        let px = ImageTools.pixelSize(of: try Data(contentsOf: drawn.url))!
        XCTAssertEqual(Int(px.width), 1920); XCTAssertEqual(Int(px.height), 1080)
    }

    func testUnsupportedPictureFormatFailsThatSlideOnly() throws {
        var files: [(String, Data)] = []
        func add(_ n: String, _ x: String) { files.append((n, Data(x.utf8))) }
        add("ppt/presentation.xml", "<p:presentation xmlns:p=\"p\" xmlns:r=\"r\"><p:sldIdLst><p:sldId id=\"256\" r:id=\"rId1\"/></p:sldIdLst></p:presentation>")
        add("ppt/_rels/presentation.xml.rels", "<Relationships><Relationship Id=\"rId1\" Type=\"x/slide\" Target=\"slides/slide1.xml\"/></Relationships>")
        add("ppt/slides/slide1.xml", "<p:sld xmlns:a=\"a\" xmlns:p=\"p\" xmlns:r=\"r\"><p:cSld><p:spTree><p:pic><p:nvPicPr><p:cNvPr id=\"1\" name=\"x\"/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId9\"/></p:blipFill></p:pic></p:spTree></p:cSld></p:sld>")
        add("ppt/slides/_rels/slide1.xml.rels", "<Relationships><Relationship Id=\"rId9\" Type=\"x/image\" Target=\"../media/image1.emf\"/></Relationships>")
        files.append(("ppt/media/image1.emf", Data(count: 10)))
        let url = try ImportSamples.write(ZipWriter.make(files), named: "Emf.pptx", in: dir)
        let s = try ImportSession.open(urls: [url])
        XCTAssertEqual(s.entries[0].style, .picture)
        XCTAssertFalse(s.entries[0].included)
        XCTAssertNotNil(s.entries[0].warning)
        XCTAssertThrowsError(try s.plan(s.entries[0], options: ImportPlanOptions(mode: .deck))) {
            XCTAssertTrue(($0 as? ChurchError)?.message.contains("emf") == true)
        }
    }

    // MARK: PDF

    func testPDFRendersPagesAt1920x1080() throws {
        let url = try ImportSamples.write(ImportSamples.pdf(pages: 3), named: "Easter Sunday.pdf", in: dir)
        let s = try ImportSession.open(urls: [url])
        XCTAssertEqual(s.kind, .pdf)
        XCTAssertEqual(s.entries.count, 3)
        XCTAssertEqual(s.entries[0].detail, "1920 x 1080")
        let parts = try s.plan(s.entries[2], options: ImportPlanOptions(mode: .deck))
        XCTAssertEqual(parts.map(\.fileName), ["Easter Sunday 03.jpg"])
        let f = try s.prepare(parts[0], directory: dir)
        XCTAssertEqual(f.contentType, "image/jpeg")
        XCTAssertEqual(f.title, "Easter Sunday 03")
        let size = ImageTools.pixelSize(of: try Data(contentsOf: f.url))!
        XCTAssertEqual(Int(size.width), 1920); XCTAssertEqual(Int(size.height), 1080)
        XCTAssertNotNil(s.thumbnail(for: s.entries[0]))
    }

    func testPDFPortraitKeepsAspect() throws {
        let url = try ImportSamples.write(ImportSamples.pdf(pages: 1, portrait: true), named: "Letter.pdf", in: dir)
        let s = try ImportSession.open(urls: [url])
        XCTAssertEqual(s.entries[0].detail, "1484 x 1920")
    }

    func testPDFLimitUntickPagesBeyond150() throws {
        let url = try ImportSamples.write(ImportSamples.pdf(pages: 152), named: "Long.pdf", in: dir)
        let s = try ImportSession.open(urls: [url])
        XCTAssertEqual(s.entries.count, 152)
        XCTAssertEqual(s.entries.filter(\.included).count, 150)
        XCTAssertFalse(s.notices.isEmpty)
        XCTAssertEqual(ImportBuilder.problem(entries: s.entries.map { var e = $0; e.included = true; return e }, placement: .append)?.contains("at most 150"), true)
        // File names pad to the width of the page count (3 digits for 152 pages).
        XCTAssertEqual(try s.plan(s.entries[6], options: ImportPlanOptions(mode: .deck))[0].fileName, "Long 007.jpg")
    }

    func testBrokenAndMixedFilesGiveMessages() throws {
        let bad = try ImportSamples.write(Data("nope".utf8), named: "bad.pdf", in: dir)
        XCTAssertThrowsError(try ImportSession.open(urls: [bad])) { XCTAssertEqual(($0 as? PDFImportError), .unreadable) }
        let ppt = try ImportSamples.write(Data("x".utf8), named: "old.ppt", in: dir)
        XCTAssertThrowsError(try ImportSession.open(urls: [ppt])) { XCTAssertTrue(($0 as? ImportError)?.errorDescription?.contains("Old .ppt") == true) }
        let pdf = try ImportSamples.write(ImportSamples.pdf(pages: 1), named: "a.pdf", in: dir)
        let png = try ImportSamples.write(ImportSamples.picture(caption: "x"), named: "a.png", in: dir)
        XCTAssertThrowsError(try ImportSession.open(urls: [pdf, png])) { XCTAssertEqual($0 as? ImportError, .mixed) }
        let key = try ImportSamples.write(Data("x".utf8), named: "a.key", in: dir)
        XCTAssertThrowsError(try ImportSession.open(urls: [key])) { XCTAssertTrue(($0 as? ImportError)?.errorDescription?.contains("Keynote") == true) }
        let txt = try ImportSamples.write(Data("x".utf8), named: "a.txt", in: dir)
        XCTAssertThrowsError(try ImportSession.open(urls: [txt])) { XCTAssertTrue(($0 as? ImportError)?.errorDescription?.contains("Choose a PDF") == true) }
        let fake = try ImportSamples.write(Data("not a zip".utf8), named: "fake.pptx", in: dir)
        XCTAssertThrowsError(try ImportSession.open(urls: [fake])) { XCTAssertEqual($0 as? PPTXError, .notPowerPoint) }
    }

    func testPicturesSessionNaturalOrderAndAsIs() throws {
        let urls = try ["Slide10.png", "Slide2.png", "Slide1.png"].map { try ImportSamples.write(ImportSamples.picture(caption: $0), named: $0, in: dir) }
        let s = try ImportSession.open(urls: urls)
        XCTAssertEqual(s.kind, .images)
        XCTAssertEqual(s.entries.map(\.title), ["Slide1", "Slide2", "Slide10"])      // natural order
        XCTAssertEqual(s.name, "Slide")                                           // shared start of the file names
        let part = try s.plan(s.entries[1], options: ImportPlanOptions(mode: .deck))[0]
        XCTAssertEqual(part.fileName, "Slide2.png")
        let f = try s.prepare(part, directory: dir)
        XCTAssertEqual(f.title, "Slide2")
        XCTAssertEqual(f.contentType, "image/png")
        XCTAssertEqual(try Data(contentsOf: f.url), try Data(contentsOf: urls[1]))   // uploaded as is
    }

    func testNaming() {
        XCTAssertEqual(ImportNaming.pageFileName(base: "Easter Sunday", number: 3, total: 12, ext: "jpg"), "Easter Sunday 03.jpg")
        XCTAssertEqual(ImportNaming.pageFileName(base: "X", number: 7, total: 120, ext: "jpg"), "X 007.jpg")
        XCTAssertEqual(ImportNaming.pageFileName(base: "X", number: 7, total: 12, ext: ""), "X 07")
        XCTAssertEqual(ImportNaming.baseName("Easter Sunday.pdf"), "Easter Sunday")
        XCTAssertEqual(ImportNaming.baseName(".pdf"), "Imported")
        XCTAssertEqual(ImportNaming.folderName(forImageFiles: ["Slide1.png", "Slide2.png"]), "Slide")
        XCTAssertEqual(ImportNaming.folderName(forImageFiles: ["IMG_1.png", "Banner.png"], today: Date(timeIntervalSince1970: 0)), "Imported pictures 1970-01-01")
        XCTAssertEqual(ImportNaming.folderName(forImageFiles: ["Welcome.png"]), "Welcome")
        XCTAssertEqual(ImportNaming.uniqueFolderName(wanted: "Easter", taken: ["easter", "Easter (2)"]), "Easter (3)")
        XCTAssertEqual(ImportNaming.uniqueFolderName(wanted: "Easter", taken: ["Other"]), "Easter")
    }

    func testImagePrepareConvertsNonWebFormats() throws {
        let png = ImportSamples.picture(caption: "x")
        let cg = CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.tiff" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        let p = ImageTools.prepare(out as Data)!
        XCTAssertEqual(p.fileExtension, "jpg")                                   // TIFF becomes JPEG
        XCTAssertEqual(ImageTools.prepare(png)?.fileExtension, "png")            // PNG goes as is
        XCTAssertNil(ImageTools.prepare(Data("not an image".utf8)))
    }

    func testTextSlideRendererFitsAndDraws() throws {
        let cg = TextSlideRenderer.render(title: "Welcome", body: String(repeating: "A long line of body text. ", count: 40), backgroundHex: "#1f3a5f", aspect: 16.0 / 9.0)!
        XCTAssertEqual(cg.width, 1920); XCTAssertEqual(cg.height, 1080)
        let four3 = TextSlideRenderer.render(title: "Hi", body: "", backgroundHex: "bad", aspect: 4.0 / 3.0)!
        XCTAssertEqual(four3.width, 1920); XCTAssertEqual(four3.height, 1440)
        let portrait = TextSlideRenderer.render(title: "Hi", body: "x", backgroundHex: "#000000", aspect: 9.0 / 16.0)!
        XCTAssertEqual(portrait.width, 1080); XCTAssertEqual(portrait.height, 1920)
        // The layout shrinks long text until it fits the 84% box.
        let (lines, height) = TextSlideRenderer.layout(title: "Welcome", body: String(repeating: "A long line of body text. ", count: 40), width: 1920, height: 1080)
        XCTAssertLessThanOrEqual(height, 1080 * 0.84 + 1)
        XCTAssertGreaterThan(lines.count, 3)
        // Pixel in a corner is the background colour (31, 58, 95).
        let data = cg.dataProvider!.data! as Data
        XCTAssertEqual(Int(data[0]), 31); XCTAssertEqual(Int(data[1]), 58); XCTAssertEqual(Int(data[2]), 95)
    }

    // MARK: Builders

    private func media(_ n: Int, kind: MediaKind = .image) -> MediaItem { MediaItem(module: "slides", title: "Deck 0\(n)", kind: kind, url: "https://x/\(n)") }

    func testDeckSlidesFromPages() throws {
        let pages = [
            ImportedPage(entryNumber: 1, media: media(1)),
            ImportedPage(entryNumber: 2, text: ImportedText(title: "Hi", body: "There"), notes: "Say hello"),
            ImportedPage(entryNumber: 3, text: ImportedText(title: "", body: "Only body")),
            ImportedPage(entryNumber: 4, text: ImportedText(title: "Only title", body: "")),
            ImportedPage(entryNumber: 5, media: media(5, kind: .video)),
        ]
        let existing = [DeckSlide.new(.blank, existing: [])]
        let slides = ImportBuilder.deckSlides(pages: pages, seconds: 8, existing: existing)
        XCTAssertEqual(slides.count, 5)
        XCTAssertEqual(Set(slides.map(\.id) + existing.map(\.id)).count, 6)
        guard case .media(let m) = slides[0].content else { return XCTFail() }
        XCTAssertEqual(m.url, "https://x/1"); XCTAssertEqual(m.seconds, 8); XCTAssertEqual(m.fit, .contain); XCTAssertEqual(m.mediaKind, .image)
        XCTAssertEqual(slides[0].background, .solid("#000000"))
        guard case .text(let t) = slides[1].content else { return XCTFail() }
        XCTAssertEqual(t.title, "Hi"); XCTAssertEqual(t.layout, .titleBody); XCTAssertEqual(t.seconds, 8); XCTAssertEqual(slides[1].notes, "Say hello")
        XCTAssertNil(slides[1].background)
        guard case .text(let t3) = slides[2].content, case .text(let t4) = slides[3].content else { return XCTFail() }
        XCTAssertEqual(t3.layout, .body); XCTAssertEqual(t4.layout, .title)
        guard case .media(let v) = slides[4].content else { return XCTFail() }
        XCTAssertEqual(v.mediaKind, .video); XCTAssertEqual(v.audio, true); XCTAssertNil(v.seconds)
        XCTAssertTrue(slides.allSatisfy { $0.problem == nil })
        XCTAssertEqual(DeckSlide(object: slides[0].object), slides[0])               // survives the JSON round trip
        guard case .media(let nm) = ImportBuilder.deckSlides(pages: pages, seconds: nil, existing: [])[0].content else { return XCTFail() }
        XCTAssertNil(nm.seconds)                                                     // wait for Next
    }

    func testKidsPlaylistItemsFromPages() {
        let pages = [ImportedPage(entryNumber: 1, media: media(1)), ImportedPage(entryNumber: 2, media: media(2, kind: .video)), ImportedPage(entryNumber: 3, text: ImportedText(title: "x", body: "y"))]
        let items = ImportBuilder.playlistItems(pages: pages, seconds: 10)
        XCTAssertEqual(items.count, 2)                                              // text pages are pictures by now; stray text is ignored
        guard case .image(let c) = items[0].content, case .video(let v) = items[1].content else { return XCTFail() }
        XCTAssertEqual(c.seconds, 10); XCTAssertEqual(c.url, "https://x/1"); XCTAssertEqual(c.title, "Deck 01")
        XCTAssertNil(v.seconds); XCTAssertFalse(v.writesSeconds)
        XCTAssertTrue(items.allSatisfy { $0.problem == nil })
        guard case .image(let w) = ImportBuilder.playlistItems(pages: pages, seconds: nil)[0].content else { return XCTFail() }
        XCTAssertNil(w.seconds)
    }

    func testPlacementAndLimitsProblem() {
        var a = [1, 2, 3]
        XCTAssertEqual(ImportBuilder.insert([9, 8], into: &a, placement: .after(1)), 1)
        XCTAssertEqual(a, [1, 9, 8, 2, 3])
        XCTAssertEqual(ImportBuilder.insert([7], into: &a, placement: .after(99)), 5)
        XCTAssertEqual(ImportBuilder.insert([6], into: &a, placement: .after(0)), 0)
        XCTAssertEqual(ImportBuilder.insert([5], into: &a, placement: .append), 7)
        XCTAssertEqual(a, [6, 1, 9, 8, 2, 3, 7, 5])
        let e = ImportEntry(number: 1, title: "t", payload: .pdfPage(1), style: .picture)
        XCTAssertEqual(ImportBuilder.problem(entries: [], placement: .append), "Tick at least one page to import.")
        XCTAssertNotNil(ImportBuilder.problem(entries: [e], placement: .newItem(name: "  ")))
        XCTAssertNil(ImportBuilder.problem(entries: [e], placement: .newItem(name: "Welcome")))
        XCTAssertNil(ImportBuilder.defaultSeconds(forDeck: true)); XCTAssertEqual(ImportBuilder.defaultSeconds(forDeck: false), 10)
    }
}
