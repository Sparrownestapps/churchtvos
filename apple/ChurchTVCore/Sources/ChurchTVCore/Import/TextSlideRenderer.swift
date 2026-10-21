import Foundation
import CoreGraphics
import CoreText

/// Draws a PowerPoint text slide as a picture (Kids playlists have no text slide). Same rules as renderTextSlideFile in
/// dashboard/src/importer/pdf.ts: solid background (the church colour), white centred text with a soft shadow, title 9% of the
/// height (heavy), body 5.5% (medium), wrapped inside an 84% x 84% box and shrunk in 5% steps until it fits.
public enum TextSlideRenderer {
    struct Line { var text: String; var size: CGFloat; var bold: Bool; var gap: CGFloat = 0 }

    public static func render(title: String, body: String, backgroundHex: String, aspect: Double, longEdge: Int = ImportLimits.renderLongEdge) -> CGImage? {
        let w = aspect >= 1 ? longEdge : Int((Double(longEdge) * aspect).rounded())
        let h = aspect >= 1 ? Int((Double(longEdge) / aspect).rounded()) : longEdge
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rgb = ColorTools.rgb(backgroundHex) ?? ColorTools.rgb(ImportLimits.kidsBackgroundDefault) ?? (31, 58, 95)
        ctx.setFillColor(ImageTools.srgb(CGFloat(rgb.r) / 255, CGFloat(rgb.g) / 255, CGFloat(rgb.b) / 255))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let (lines, height) = layout(title: title, body: body, width: CGFloat(w), height: CGFloat(h))
        ctx.setShadow(offset: .zero, blur: CGFloat(h) * 0.01, color: ImageTools.srgb(0, 0, 0, 0.45))
        var y = (CGFloat(h) - height) / 2          // distance from the top
        for l in lines {
            let font = self.font(l.size, bold: l.bold)
            let ct = ctLine(l.text, font)
            let width = CTLineGetTypographicBounds(ct, nil, nil, nil)
            ctx.textPosition = CGPoint(x: (CGFloat(w) - CGFloat(width)) / 2, y: CGFloat(h) - y - CTFontGetAscent(font))
            CTLineDraw(ct, ctx)
            y += l.size * 1.2 + l.gap
        }
        return ctx.makeImage()
    }

    static func font(_ size: CGFloat, bold: Bool) -> CTFont { CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue-Medium") as CFString, size, nil) }

    static func ctLine(_ text: String, _ font: CTFont) -> CTLine {
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ImageTools.srgb(1, 1, 1)]
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!)
    }

    static func wrap(_ text: String, size: CGFloat, bold: Bool, maxWidth: CGFloat) -> [String] {
        let font = self.font(size, bold: bold)
        func width(_ s: String) -> CGFloat { CGFloat(CTLineGetTypographicBounds(ctLine(s, font), nil, nil, nil)) }
        var out: [String] = []
        for para in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in para.split(whereSeparator: \.isWhitespace) {
                let next = line.isEmpty ? String(word) : "\(line) \(word)"
                if width(next) <= maxWidth || line.isEmpty { line = next } else { out.append(line); line = String(word) }
            }
            out.append(line)
        }
        return out
    }

    static func layout(title: String, body: String, width w: CGFloat, height h: CGFloat) -> ([Line], CGFloat) {
        let maxW = w * 0.84, maxH = h * 0.84
        let t = title.trimmed, b = body.trimmed
        var k: CGFloat = 1
        while true {
            var items: [Line] = []
            let ts = h * 0.09 * k, bs = h * 0.055 * k
            if !t.isEmpty { for l in wrap(t, size: ts, bold: true, maxWidth: maxW) { items.append(Line(text: l, size: ts, bold: true)) } }
            if !t.isEmpty && !b.isEmpty, !items.isEmpty { items[items.count - 1].gap = ts * 0.4 }
            if !b.isEmpty { for l in wrap(b, size: bs, bold: false, maxWidth: maxW) { items.append(Line(text: l, size: bs, bold: false)) } }
            let height = items.reduce(0) { $0 + $1.size * 1.2 + $1.gap }
            if height <= maxH || k < 0.35 { return (items, height) }
            k *= 0.95
        }
    }
}
