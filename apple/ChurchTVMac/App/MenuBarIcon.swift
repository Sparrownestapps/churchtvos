import AppKit
import SwiftUI
import ChurchTVCore

extension MenuBarStatus {
    var dotColor: NSColor {
        switch self {
        case .allOnline: return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .someOffline: return NSColor(srgbRed: 1.0, green: 0.70, blue: 0.0, alpha: 1)
        case .signedOut, .noScreens: return NSColor(white: 0.60, alpha: 1)
        }
    }
    var swiftUIColor: Color { Color(nsColor: dotColor) }
}

enum MenuBarIcon {
    /// A TV glyph with a coloured status dot (bottom right). Drawn lazily so the glyph follows the menu bar's light/dark appearance.
    static func image(for status: MenuBarStatus) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let glyph = NSImage(systemSymbolName: "tv", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let tinted = NSImage(size: glyph.size, flipped: false) { r in
                    glyph.draw(in: r)
                    NSColor.labelColor.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                let g = tinted.size
                tinted.draw(in: NSRect(x: 0, y: (rect.height - g.height) / 2 + 0.5, width: g.width, height: g.height))
            }
            let dot = NSRect(x: rect.width - 9, y: 0.5, width: 8, height: 8)
            // A thin ring of the menu bar colour keeps the dot readable on the glyph.
            NSColor.windowBackgroundColor.withAlphaComponent(0.0).set()
            status.dotColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.25, dy: 0.25)); ring.lineWidth = 0.5; ring.stroke()
            return true
        }
        img.isTemplate = false
        return img
    }
}
