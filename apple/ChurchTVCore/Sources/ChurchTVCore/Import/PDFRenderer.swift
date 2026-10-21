import Foundation
import CoreGraphics

public enum PDFImportError: Error, LocalizedError, Equatable {
    case unreadable
    case passwordProtected
    case noPages
    case tooLarge(Int64)
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "This PDF could not be opened. It may be damaged."
        case .passwordProtected: return "This PDF is password protected. Open it, export a copy without the password and try again."
        case .noPages: return "This PDF has no pages."
        case .tooLarge(let n): return "This file is \(Formatting.bytes(n)). The limit is \(ImportLimits.documentLimitText)."
        }
    }
}

/// Renders PDF pages to pictures with CoreGraphics (no PDFKit needed, so the same code runs on iOS and macOS).
/// Not thread safe: use one page at a time.
public final class PDFSource: @unchecked Sendable {
    private let doc: CGPDFDocument
    public let pageCount: Int

    public init(url: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if size > ImportLimits.maxDocumentBytes { throw PDFImportError.tooLarge(size) }
        guard let d = CGPDFDocument(url as CFURL) else { throw PDFImportError.unreadable }
        if d.isEncrypted && !d.isUnlocked {
            // Many PDFs are "encrypted" with an empty user password (they only restrict printing or copying).
            guard d.unlockWithPassword("") else { throw PDFImportError.passwordProtected }
        }
        doc = d
        pageCount = d.numberOfPages
        if pageCount == 0 { throw PDFImportError.noPages }
    }

    /// Size of a page in points as it is shown (crop box, rotation applied). `page` is 1-based.
    public func pageSize(_ page: Int) -> CGSize? {
        guard let p = doc.page(at: page) else { return nil }
        let r = p.getBoxRect(.cropBox)
        guard r.width > 0, r.height > 0 else { return nil }
        let rot = ((p.rotationAngle % 360) + 360) % 360
        return (rot == 90 || rot == 270) ? CGSize(width: r.height, height: r.width) : r.size
    }

    /// Pixel size a page is rendered at: the longest side is `longEdge`, the page's aspect ratio is kept (16:9 slides give 1920x1080).
    public func renderSize(_ page: Int, longEdge: Int) -> (width: Int, height: Int)? {
        guard let s = pageSize(page) else { return nil }
        let scale = CGFloat(longEdge) / max(s.width, s.height)
        return (max(1, Int((s.width * scale).rounded())), max(1, Int((s.height * scale).rounded())))
    }

    /// The page drawn on a white background. `page` is 1-based.
    public func render(page: Int, longEdge: Int = 1920) -> CGImage? {
        guard let p = doc.page(at: page), let size = renderSize(page, longEdge: longEdge),
              let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.concatenate(p.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(p)
        return ctx.makeImage()
    }

    public func renderJPEG(page: Int, longEdge: Int = 1920, quality: Double = 0.88) -> Data? {
        render(page: page, longEdge: longEdge).flatMap { ImageTools.jpeg($0, quality: quality) }
    }
}
