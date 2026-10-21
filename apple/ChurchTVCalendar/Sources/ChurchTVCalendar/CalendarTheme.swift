import SwiftUI
import ChurchTVCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// A colour with a light and a dark value (follows the system appearance).
    init(light: UInt32, dark: UInt32) {
        func rgb(_ v: UInt32) -> (Double, Double, Double) { (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255) }
        #if canImport(UIKit)
        self.init(uiColor: UIColor { t in
            let (r, g, b) = rgb(t.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { a in
            let isDark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = rgb(isDark ? dark : light)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
        #endif
    }
}

/// Colours per kind of block, the same as the website's calendar.css (one-time Kids green, repeating Kids teal, one-time Slides amber,
/// repeating Slides rose, Signage blue, module switch purple), light and dark.
struct CalendarPalette {
    let background: Color, border: Color, foreground: Color

    static func of(_ style: CalendarEventStyle) -> CalendarPalette {
        switch style {
        case .kidsOneTime: return .init(background: Color(light: 0xD9EFE3, dark: 0x1D3A2D), border: Color(light: 0x2E7D5B, dark: 0x4FB586), foreground: Color(light: 0x174A33, dark: 0xCDEEDC))
        case .kidsRepeating: return .init(background: Color(light: 0xD6ECF1, dark: 0x1A3840), border: Color(light: 0x1B7F93, dark: 0x4CB6C9), foreground: Color(light: 0x0F4A58, dark: 0xCBEAF0))
        case .slidesOneTime: return .init(background: Color(light: 0xFBE8D2, dark: 0x3D2A16), border: Color(light: 0xC26A14, dark: 0xE8995A), foreground: Color(light: 0x6E3705, dark: 0xF7DCC3))
        case .slidesRepeating: return .init(background: Color(light: 0xF7DDE6, dark: 0x402230), border: Color(light: 0xB23A68, dark: 0xE57C9F), foreground: Color(light: 0x6B1B3D, dark: 0xF7D3DF))
        case .signage: return .init(background: Color(light: 0xDDE6FA, dark: 0x212F57), border: Color(light: 0x3B63C4, dark: 0x7D9CF0), foreground: Color(light: 0x1D3680, dark: 0xD9E2FF))
        case .moduleSwitch: return .init(background: Color(light: 0xE8E0F3, dark: 0x35295A), border: Color(light: 0x7054A8, dark: 0xA98EE0), foreground: Color(light: 0x3F2A70, dark: 0xE6DCFA))
        }
    }

    /// Tint behind the grid for the module a screen is running.
    static func band(_ module: String) -> Color {
        switch module {
        case "kids": return Color(light: 0x2E7D5B, dark: 0x4FB586).opacity(0.10)
        case "signage": return Color(light: 0x3B63C4, dark: 0x7D9CF0).opacity(0.10)
        case "slides": return Color(light: 0xC26A14, dark: 0xE8995A).opacity(0.10)
        case "off": return Color.gray.opacity(0.16)
        default: return Color(light: 0x7054A8, dark: 0xA98EE0).opacity(0.10)
        }
    }
}
