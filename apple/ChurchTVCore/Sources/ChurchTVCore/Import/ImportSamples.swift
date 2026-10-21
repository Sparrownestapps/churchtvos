import Foundation
import CoreGraphics
import CoreText

/// Builds small sample files: a PDF, a .pptx and a picture. Used by the unit tests and by the debug screenshots; never by the shipped UI.
public enum ImportSamples {
    // MARK: Picture

    /// A 1920x1080 gradient PNG with a caption.
    public static func picture(caption: String, hueA: (CGFloat, CGFloat, CGFloat) = (0.11, 0.30, 0.55), hueB: (CGFloat, CGFloat, CGFloat) = (0.95, 0.55, 0.20)) -> Data {
        let w = 1920, h = 1080
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let colors = [ImageTools.srgb(hueA.0, hueA.1, hueA.2), ImageTools.srgb(hueB.0, hueB.1, hueB.2)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
        draw(caption, in: ctx, rect: CGRect(x: 0, y: 0, width: w, height: h), size: 150, color: ImageTools.srgb(1, 1, 1))
        return ImageTools.png(ctx.makeImage()!)!
    }

    private static func draw(_ text: String, in ctx: CGContext, rect: CGRect, size: CGFloat, color: CGColor) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2)
        CTLineDraw(line, ctx)
    }

    // MARK: PDF

    /// A PDF with `pages` landscape (16:9) pages, each a coloured page with its number.
    public static func pdf(pages: Int = 3, portrait: Bool = false) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: portrait ? 612 : 960, height: portrait ? 792 : 540)
        let consumer = CGDataConsumer(data: data)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        let palette: [(CGFloat, CGFloat, CGFloat)] = [(0.11, 0.30, 0.55), (0.18, 0.49, 0.36), (0.70, 0.15, 0.12), (0.45, 0.20, 0.65)]
        for n in 1...max(1, pages) {
            ctx.beginPDFPage(nil)
            let c = palette[(n - 1) % palette.count]
            ctx.setFillColor(ImageTools.srgb(c.0, c.1, c.2))
            ctx.fill(box)
            draw("Page \(n)", in: ctx, rect: box, size: portrait ? 90 : 110, color: ImageTools.srgb(1, 1, 1))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    // MARK: PPTX

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func shape(id: Int, name: String, ph: String?, x: Int, y: Int, cx: Int = 9_000_000, cy: Int = 1_000_000, paragraphs: [String]) -> String {
        let phXML = ph.map { "<p:ph type=\"\($0)\"/>" } ?? ""
        let paras = paragraphs.map { p -> String in
            if p.isEmpty { return "<a:p/>" }
            let lvl = p.hasPrefix(">")        // ">text" = second level paragraph
            return "<a:p>\(lvl ? "<a:pPr lvl=\"1\"/>" : "")<a:r><a:rPr lang=\"en-US\"/><a:t>\(esc(lvl ? String(p.dropFirst()) : p))</a:t></a:r></a:p>"
        }.joined()
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr/><p:nvPr>\(phXML)</p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>\(paras)</p:txBody></p:sp>"
    }

    private static func slideXML(shapes: String, show: Bool = true, extra: String = "") -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"\(show ? "" : " show=\"0\"")><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>\(shapes)\(extra)</p:spTree></p:cSld></p:sld>"
    }

    private static func notesXML(_ text: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:notes xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>\(esc(text))</a:t></a:r></a:p></p:txBody></p:sp>"
            + "</p:spTree></p:cSld></p:notes>"
    }

    private static func rels(_ items: [(id: String, type: String, target: String)]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + items.map { "<Relationship Id=\"\($0.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\($0.type)\" Target=\"\($0.target)\"/>" }.joined() + "</Relationships>"
    }

    /// A 7 slide presentation:
    /// 1 title + subtitle (with notes); 2 title and two columns written right column first (tests reading order);
    /// 3 picture only; 4 a text box without title placeholder; 5 hidden slide; 6 a slide with only a footer (empty); 7 title, body, a small picture and a video clip.
    public static func pptx() -> Data {
        let img = picture(caption: "Welcome")
        var files: [(String, Data)] = []
        func add(_ n: String, _ s: String) { files.append((n, Data(s.utf8))) }
        add("[Content_Types].xml", "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/></Types>")
        add("ppt/presentation.xml", "<?xml version=\"1.0\"?><p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><p:sldIdLst>"
            + (1...7).map { "<p:sldId id=\"\(255 + $0)\" r:id=\"rId\($0)\"/>" }.joined() + "</p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\"/></p:presentation>")
        add("ppt/_rels/presentation.xml.rels", rels((1...7).map { ("rId\($0)", "slide", "slides/slide\($0).xml") }))

        add("ppt/slides/slide1.xml", slideXML(shapes:
            shape(id: 3, name: "Subtitle", ph: "subTitle", x: 1_000_000, y: 3_500_000, paragraphs: ["Sunday 10:30 AM"])
            + shape(id: 2, name: "Title", ph: "ctrTitle", x: 1_000_000, y: 1_500_000, paragraphs: ["Welcome to Forward Church"])
            + shape(id: 4, name: "Footer", ph: "ftr", x: 0, y: 6_400_000, paragraphs: ["footer text"])))
        add("ppt/slides/_rels/slide1.xml.rels", rels([("rId1", "notesSlide", "../notesSlides/notesSlide1.xml")]))
        add("ppt/notesSlides/notesSlide1.xml", notesXML("Greet everyone. Mention the coffee bar."))

        add("ppt/slides/slide2.xml", slideXML(shapes:
            shape(id: 3, name: "Right", ph: nil, x: 6_500_000, y: 1_800_000, cx: 5_000_000, paragraphs: ["Kids check-in opens 10:00", "Nursery to age 3"])
            + shape(id: 4, name: "Left", ph: nil, x: 700_000, y: 1_800_000, cx: 5_000_000, paragraphs: ["Parking team needs help", "", "", "Sign up at the Welcome desk"])
            + shape(id: 2, name: "Title", ph: "title", x: 700_000, y: 400_000, paragraphs: ["This week at Forward"])))
        add("ppt/slides/_rels/slide2.xml.rels", rels([]))

        let pic = "<p:pic><p:nvPicPr><p:cNvPr id=\"5\" name=\"Welcome picture\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId2\"/></p:blipFill><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"12192000\" cy=\"6858000\"/></a:xfrm></p:spPr></p:pic>"
        add("ppt/slides/slide3.xml", slideXML(shapes: pic))
        add("ppt/slides/_rels/slide3.xml.rels", rels([("rId2", "image", "../media/image1.png")]))
        files.append(("ppt/media/image1.png", img))

        add("ppt/slides/slide4.xml", slideXML(shapes: shape(id: 2, name: "TextBox", ph: nil, x: 1_000_000, y: 2_000_000, paragraphs: ["Offering: give online at forward.church"])))
        add("ppt/slides/_rels/slide4.xml.rels", rels([]))

        add("ppt/slides/slide5.xml", slideXML(shapes: shape(id: 2, name: "Title", ph: "title", x: 700_000, y: 400_000, paragraphs: ["Hidden backup slide"]), show: false))
        add("ppt/slides/_rels/slide5.xml.rels", rels([]))

        add("ppt/slides/slide6.xml", slideXML(shapes: shape(id: 2, name: "Slide Number", ph: "sldNum", x: 0, y: 6_400_000, paragraphs: ["6"])))
        add("ppt/slides/_rels/slide6.xml.rels", rels([]))

        // 7: a text slide with a small picture and a video clip (relationship of type video).
        let smallPic = "<p:pic><p:nvPicPr><p:cNvPr id=\"6\" name=\"Logo\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId2\"/></p:blipFill><p:spPr><a:xfrm><a:off x=\"100000\" y=\"100000\"/><a:ext cx=\"1000000\" cy=\"1000000\"/></a:xfrm></p:spPr></p:pic>"
        let videoPic = "<p:pic><p:nvPicPr><p:cNvPr id=\"7\" name=\"Clip\"/><p:cNvPicPr/><p:nvPr><a:videoFile r:link=\"rId3\"/></p:nvPr></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId2\"/></p:blipFill><p:spPr><a:xfrm><a:off x=\"1000000\" y=\"3000000\"/><a:ext cx=\"4000000\" cy=\"2250000\"/></a:xfrm></p:spPr></p:pic>"
        add("ppt/slides/slide7.xml", slideXML(shapes:
            shape(id: 2, name: "Title", ph: "title", x: 700_000, y: 400_000, paragraphs: ["Watch this"])
            + shape(id: 3, name: "Body", ph: "body", x: 700_000, y: 1_500_000, paragraphs: ["Then talk about it", ">Second level point"])
            + smallPic + videoPic))
        add("ppt/slides/_rels/slide7.xml.rels", rels([("rId2", "image", "../media/image1.png"), ("rId3", "video", "../media/clip1.mp4")]))
        files.append(("ppt/media/clip1.mp4", Data(repeating: 0x42, count: 2048)))
        return ZipWriter.make(files)
    }

    /// Writes a sample into `directory` and returns its URL.
    public static func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
