import Foundation

// MARK: - Small enums (raw values are the JSON values)

public enum ContentFit: String, Hashable, Sendable, CaseIterable { case cover, contain }
/// Text alignment of a slide or theme. (Not called TextAlignment: SwiftUI has a type with that name.)
public enum SlideAlign: String, Hashable, Sendable, CaseIterable { case left, center }
public enum SlideLayout: String, Hashable, Sendable, CaseIterable {
    case titleBody = "title_body", title, body, lowerThird = "lower_third"
}
public enum TextPosition: String, Hashable, Sendable, CaseIterable { case center, lower, top }
public enum ThemeFont: String, Hashable, Sendable, CaseIterable { case lato, julius }
public enum LogoPosition: String, Hashable, Sendable, CaseIterable {
    case bottomLeft = "bottom_left", bottomRight = "bottom_right", topLeft = "top_left", topRight = "top_right"
}

// MARK: - Colour maths (dashboard/src/theme.ts, WCAG relative luminance)

public enum ColorTools {
    /// '#RRGGBB'
    public static func isHex(_ s: String?) -> Bool {
        guard let s, s.count == 7, s.first == "#" else { return false }
        return s.dropFirst().allSatisfy { $0.isHexDigit }
    }

    public static func rgb(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        guard isHex(hex) else { return nil }
        let v = Array(hex.dropFirst())
        func pair(_ i: Int) -> Int { Int(String(v[i...i + 1]), radix: 16) ?? 0 }
        return (pair(0), pair(2), pair(4))
    }

    public static func hex(r: Int, g: Int, b: Int) -> String {
        func c(_ v: Int) -> String { String(format: "%02x", max(0, min(255, v))) }
        return "#" + c(r) + c(g) + c(b)
    }

    /// 0 (black) ... 1 (white).
    public static func luminance(_ hex: String) -> Double {
        guard let c = rgb(hex) else { return 0 }
        func lin(_ v: Int) -> Double { let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    public static func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Text colour for a sign background: near-black on light, white on dark.
    public static func signTextColor(_ bg: String) -> String { luminance(bg) > 0.5 ? "#111111" : "#ffffff" }

    /// Mixes a colour towards black (dim 0 = unchanged, 0.8 = nearly black).
    public static func dimmed(_ hex: String, _ dim: Double = 0) -> String {
        guard let c = rgb(hex) else { return hex }
        let k = 1 - min(0.8, max(0, dim))
        return Self.hex(r: Int((Double(c.r) * k).rounded()), g: Int((Double(c.g) * k).rounded()), b: Int((Double(c.b) * k).rounded()))
    }
}

// MARK: - SlideBackground

/// A background layer: resolution order for a slide is slide, then deck, then theme, then the church colour.
/// One flat struct (like the TypeScript union, but easier to bind in forms): which fields matter depends on `kind`.
///  - color:    `color`, `dim`
///  - gradient: `color`, `color2`, `angle` (default 135), `dim`
///  - image/video: `mediaId`, `url`, `fit` (default cover), `color` (fill behind a 'contain' file), `dim`
public struct SlideBackground: Hashable, Sendable, RawObjectCodable {
    public enum Kind: Hashable, Sendable {
        case color, gradient, image, video
        case unknown(String)
        public var rawValue: String {
            switch self {
            case .color: return "color"
            case .gradient: return "gradient"
            case .image: return "image"
            case .video: return "video"
            case .unknown(let s): return s
            }
        }
        public init(rawValue: String) {
            switch rawValue {
            case "color": self = .color
            case "gradient": self = .gradient
            case "image": self = .image
            case "video": self = .video
            default: self = .unknown(rawValue)
            }
        }
    }

    public var kind: Kind
    public var color: String?
    public var color2: String?
    public var angle: Double?
    public var mediaId: String?
    public var url: String?
    public var fit: ContentFit?
    /// 0...0.8 black overlay.
    public var dim: Double?
    public var extra: RawObject

    public init(kind: Kind, color: String? = nil, color2: String? = nil, angle: Double? = nil, mediaId: String? = nil,
                url: String? = nil, fit: ContentFit? = nil, dim: Double? = nil, extra: RawObject = [:]) {
        self.kind = kind; self.color = color; self.color2 = color2; self.angle = angle; self.mediaId = mediaId
        self.url = url; self.fit = fit; self.dim = dim; self.extra = extra
    }

    public static func solid(_ hex: String, dim: Double? = nil) -> SlideBackground { .init(kind: .color, color: hex, dim: dim) }
    public static func gradient(_ a: String, _ b: String, angle: Double? = nil, dim: Double? = nil) -> SlideBackground {
        .init(kind: .gradient, color: a, color2: b, angle: angle, dim: dim)
    }
    public static func image(mediaId: String, url: String, fit: ContentFit? = nil, dim: Double? = nil) -> SlideBackground {
        .init(kind: .image, mediaId: mediaId, url: url, fit: fit, dim: dim)
    }
    public static func video(mediaId: String, url: String, fit: ContentFit? = nil, dim: Double? = nil) -> SlideBackground {
        .init(kind: .video, mediaId: mediaId, url: url, fit: fit, dim: dim)
    }

    public init(object: RawObject) {
        var o = object
        kind = Kind(rawValue: o.takeString("type") ?? "")
        color = o.takeString("color")
        color2 = o.takeString("color2")
        angle = o.takeDouble("angle")
        mediaId = o.takeString("media_id")
        url = o.takeString("url")
        fit = o.takeEnum("fit")
        dim = o.takeDouble("dim")
        extra = o
    }

    public var object: RawObject {
        var o = extra
        o["type"] = .string(kind.rawValue)
        o.put("color", color); o.put("color2", color2); o.put("angle", angle)
        o.put("media_id", mediaId); o.put("url", url); o.put("fit", fit); o.put("dim", dim)
        return o
    }

    /// An image or video background with no file chosen is skipped when resolving (render.ts `usable`).
    public var isUsable: Bool {
        switch kind {
        case .color, .gradient: return true
        case .image, .video: return !(url ?? "").isEmpty
        case .unknown: return false
        }
    }
    public var effectiveDim: Double { min(0.8, max(0, dim ?? 0)) }
    public var effectiveFit: ContentFit { fit ?? .cover }
    public var effectiveAngle: Double { angle ?? 135 }
}

// MARK: - ThemeConfig

public struct ThemeLogo: Hashable, Sendable {
    public var show: Bool
    public var position: LogoPosition
    public var extra: RawObject
    public init(show: Bool = false, position: LogoPosition = .bottomLeft, extra: RawObject = [:]) {
        self.show = show; self.position = position; self.extra = extra
    }
}

/// `slide_themes.config`. Every field is optional; the TV and `ResolvedTheme` fill the defaults.
/// Note: the database comment says title_size/body_size but the contract (slidesTypes.ts) and the TV use `title_scale`/`body_scale`.
public struct ThemeConfig: Hashable, Sendable, RawObjectCodable {
    public var font: ThemeFont?
    /// 0.5...1.5, default 1.
    public var titleScale: Double?
    public var bodyScale: Double?
    /// '#RRGGBB', default '#FFFFFF'.
    public var textColor: String?
    public var align: SlideAlign?
    public var position: TextPosition?
    public var shadow: Bool?
    public var outline: Bool?
    /// Percent of the screen kept clear around text, 0...20, default 8.
    public var margin: Double?
    public var background: SlideBackground?
    public var showLabels: Bool?
    public var logo: ThemeLogo?
    public var extra: RawObject

    public init(font: ThemeFont? = nil, titleScale: Double? = nil, bodyScale: Double? = nil, textColor: String? = nil,
                align: SlideAlign? = nil, position: TextPosition? = nil, shadow: Bool? = nil, outline: Bool? = nil,
                margin: Double? = nil, background: SlideBackground? = nil, showLabels: Bool? = nil, logo: ThemeLogo? = nil,
                extra: RawObject = [:]) {
        self.font = font; self.titleScale = titleScale; self.bodyScale = bodyScale; self.textColor = textColor
        self.align = align; self.position = position; self.shadow = shadow; self.outline = outline; self.margin = margin
        self.background = background; self.showLabels = showLabels; self.logo = logo; self.extra = extra
    }

    public init(object: RawObject) {
        var o = object
        font = o.takeEnum("font")
        titleScale = o.takeDouble("title_scale")
        bodyScale = o.takeDouble("body_scale")
        textColor = o.takeString("text_color")
        align = o.takeEnum("align")
        position = o.takeEnum("position")
        shadow = o.takeBool("shadow")
        outline = o.takeBool("outline")
        margin = o.takeDouble("margin")
        background = o.takeObject("background").map(SlideBackground.init(object:))
        showLabels = o.takeBool("show_labels")
        if var l = o.takeObject("logo") {
            let pos: LogoPosition = l.takeEnum("position") ?? .bottomLeft
            let show = l.takeBool("show") ?? false
            logo = ThemeLogo(show: show, position: pos, extra: l)
        } else { logo = nil }
        extra = o
    }

    public var object: RawObject {
        var o = extra
        o.put("font", font); o.put("title_scale", titleScale); o.put("body_scale", bodyScale); o.put("text_color", textColor)
        o.put("align", align); o.put("position", position); o.put("shadow", shadow); o.put("outline", outline)
        o.put("margin", margin); o.put("show_labels", showLabels)
        if let background { o["background"] = .object(background.object) }
        if let logo {
            var l = logo.extra
            l["show"] = .bool(logo.show); l["position"] = .string(logo.position.rawValue)
            o["logo"] = .object(l)
        }
        return o
    }

    /// The website's first preset ("Classic dark blue"): the starting point for a new theme.
    public static var standard: ThemeConfig { ThemePreset.all[0].config }
}

/// The website's theme presets (ThemesPage.tsx).
public struct ThemePreset: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var blurb: String
    public var config: ThemeConfig

    private static func make(_ text: String, bg: SlideBackground, shadow: Bool) -> ThemeConfig {
        ThemeConfig(font: .lato, titleScale: 1, bodyScale: 1, textColor: text, align: .center, position: .center, shadow: shadow, outline: false,
                    margin: 8, background: bg, showLabels: true, logo: ThemeLogo(show: false, position: .bottomLeft))
    }

    public static let all: [ThemePreset] = [
        ThemePreset(id: "classic", name: "Classic dark blue", blurb: "White text on deep blue. Safe everywhere.",
                    config: make("#FFFFFF", bg: .solid("#1f3a5f"), shadow: true)),
        ThemePreset(id: "warm", name: "Warm light", blurb: "Dark text on a soft cream background.",
                    config: make("#2B2118", bg: .solid("#F6EFE3"), shadow: false)),
        ThemePreset(id: "video", name: "Video-ready", blurb: "Shadow on and the background dimmed 40%, for words over a video or photo.",
                    config: make("#FFFFFF", bg: .solid("#101820", dim: 0.4), shadow: true)),
    ]
}

/// A row of `slide_themes`.
public struct SlideTheme: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var organizationId: UUID
    public var name: String
    public var config: ThemeConfig
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID = UUID(), organizationId: UUID, name: String, config: ThemeConfig = .standard, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id; self.organizationId = organizationId; self.name = name; self.config = config
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, config
        case organizationId = "organization_id", createdAt = "created_at", updatedAt = "updated_at"
    }
}
