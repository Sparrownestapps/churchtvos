import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// An image ready to upload.
public struct PreparedImage: Sendable {
    public var data: Data
    public var fileExtension: String
    public var contentType: String
    public var pixelSize: CGSize
}

/// ImageIO helpers shared by the PDF, PowerPoint and picture importers. No UI types, so they work on iOS and macOS.
public enum ImageTools {
    /// A colour in sRGB (CGColor(red:green:blue:alpha:) is Generic RGB, which shifts the colours).
    public static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
    }

    /// Longest side of an imported picture; TVs are at most 4K.
    public static let maxPixels = 3840

    public static func jpeg(_ cg: CGImage, quality: Double = 0.88) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    public static func png(_ cg: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Pixel size from the file header, or nil if it is not an image the system can read.
    public static func pixelSize(of data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Picture bytes ready to upload. JPEG, PNG, GIF and WebP go as they are (the importer uploads "as is", up to the upload limit);
    /// everything else the system can decode (HEIC, TIFF, BMP) becomes JPEG, or PNG when it has transparency, scaled to at most 3840 px.
    /// Returns nil when the data is not a readable picture (EMF/WMF/SVG from PowerPoint, for example).
    public static func prepare(_ data: Data) -> PreparedImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0, let size = pixelSize(of: data) else { return nil }
        let type = CGImageSourceGetType(src) as String?
        if Int64(data.count) <= ImportLimits.maxUploadBytes {
            switch type {
            case UTType.jpeg.identifier: return PreparedImage(data: data, fileExtension: "jpg", contentType: "image/jpeg", pixelSize: size)
            case UTType.png.identifier: return PreparedImage(data: data, fileExtension: "png", contentType: "image/png", pixelSize: size)
            case UTType.gif.identifier: return PreparedImage(data: data, fileExtension: "gif", contentType: "image/gif", pixelSize: size)
            case UTType.webP.identifier: return PreparedImage(data: data, fileExtension: "webp", contentType: "image/webp", pixelSize: size)
            default: break
            }
        }
        let longest = max(size.width, size.height)
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: min(Int(longest), maxPixels), kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let hasAlpha: Bool
        switch cg.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false; default: hasAlpha = true }
        let out = CGSize(width: cg.width, height: cg.height)
        if hasAlpha, type == UTType.tiff.identifier || type == UTType.png.identifier, let d = png(cg), Int64(d.count) <= ImportLimits.maxUploadBytes {
            return PreparedImage(data: d, fileExtension: "png", contentType: "image/png", pixelSize: out)
        }
        guard let d = jpeg(flattened(cg), quality: ImportLimits.jpegQuality) else { return nil }
        return PreparedImage(data: d, fileExtension: "jpg", contentType: "image/jpeg", pixelSize: out)
    }

    /// Draws on white so JPEG (no alpha) does not turn transparent areas black.
    static func flattened(_ cg: CGImage) -> CGImage {
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cg }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    /// Small JPEG for the preview list.
    public static func thumbnail(of data: Data, maxPixel: Int = 480) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source: src, maxPixel: maxPixel)
    }

    public static func thumbnail(ofFile url: URL, maxPixel: Int = 480) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source: src, maxPixel: maxPixel)
    }

    private static func thumbnail(source: CGImageSource, maxPixel: Int) -> Data? {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        return jpeg(flattened(cg), quality: 0.7)
    }
}
