import SwiftUI
import ChurchTVCore

/// A native, still preview of ONE TV screen, drawn with the same proportions as the website (dashboard/src/slides/render.ts):
/// every size is a percentage of the frame HEIGHT, text auto-fits its box, the dim overlay and the theme's colour, size, position,
/// alignment, shadow, outline and margin all apply.
///
/// Use `SlidePreview(frame:theme:background:)` when you already have a `PreviewFrame`, or the deck convenience initialiser:
/// ```swift
/// SlidePreview(slide: slide, deckBackground: deck.background, theme: theme?.config, songs: model.songLookup)
/// ```
/// `shape` is `.landscape` (16:9) or `.portrait` (9:16). `live: true` plays video backgrounds (muted, looping); the default shows a poster.
/// The preview scales to whatever width it is given, so put it in a `.frame(width:)` or a list row.
struct SlidePreview: View {
    var frame: PreviewFrame
    var theme: ResolvedTheme = ResolvedTheme()
    var background: SlideBackground = .solid(SlideMetrics.defaultNavy)
    var shape: FrameShape = .landscape
    /// The church logo, drawn in the corner the theme asks for (only when the theme shows it).
    var logoURL: URL?
    var live = false

    init(frame: PreviewFrame, theme: ResolvedTheme = ResolvedTheme(), background: SlideBackground = .solid(SlideMetrics.defaultNavy),
         shape: FrameShape = .landscape, logoURL: URL? = nil, live: Bool = false) {
        self.frame = frame; self.theme = theme; self.background = background; self.shape = shape; self.logoURL = logoURL; self.live = live
    }

    /// One screen of a deck slide. `frameIndex` picks the screen of a song slide (title screen, then one per lyric slide).
    init(slide: DeckSlide, frameIndex: Int = 0, deckBackground: SlideBackground? = nil, theme: ThemeConfig? = nil, songs: SongLookup = [:],
         defaultColor: String = SlideMetrics.defaultNavy, shape: FrameShape = .landscape, logoURL: URL? = nil, live: Bool = false) {
        let frames = SlideRender.frames(for: slide, songs: songs)
        self.init(frame: frames[min(max(0, frameIndex), frames.count - 1)], theme: ResolvedTheme(theme),
                  background: BackgroundResolver.resolve(slide: slide.background, deck: deckBackground, theme: theme?.background, fallbackColor: defaultColor),
                  shape: shape, logoURL: logoURL, live: live)
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let fill = effectiveBackground
            ZStack {
                BackgroundLayer(background: fill, live: live)
                if dim > 0 { Color.black.opacity(dim) }
                content(width: w, height: h)
                if theme.logo.show, let logoURL, !isBlankOrStream {
                    LogoView(url: logoURL, position: theme.logo.position, width: w, height: h)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: max(3, h * 0.02)))
            .overlay(RoundedRectangle(cornerRadius: max(3, h * 0.02)).stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
        .aspectRatio(shape == .landscape ? 16.0 / 9.0 : 9.0 / 16.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shape == .landscape ? "Landscape" : "Portrait") preview: \(Self.describe(frame))")
        .accessibilityAddTraits(.isImage)
    }

    private var isBlankOrStream: Bool {
        switch frame { case .blank, .stream, .ndi: return true; default: return false }
    }

    private var effectiveBackground: SlideBackground {
        switch frame {
        case .blank(let color): return .solid(color)
        case .stream, .ndi: return .solid("#000000")
        case .sign(let s): return .solid(s.background)
        default: return background
        }
    }

    private var dim: Double {
        switch frame { case .blank, .stream, .ndi, .sign: return 0; default: return background.effectiveDim }
    }

    @ViewBuilder private func content(width w: Double, height h: Double) -> some View {
        switch frame {
        case .media(let url, let kind, let fit):
            if url.isEmpty {
                Text("Choose a file").font(.system(size: h * 0.05)).opacity(0.8).foregroundStyle(.white)
            } else {
                MediaThumbnail(url: url, kind: kind, fit: fit, showsBadge: false)
                    .overlay(alignment: .bottomTrailing) {
                        if kind == .video {
                            Text("▶ Video").font(.system(size: h * 0.034)).foregroundStyle(.white)
                                .padding(.horizontal, h * 0.016).padding(.vertical, h * 0.005)
                                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: h * 0.01))
                                .padding(.trailing, w * 0.03).padding(.bottom, h * 0.04)
                        }
                    }
            }
        case .stream(let title):
            VStack(spacing: h * 0.024) {
                Text("● LIVE").font(.system(size: h * 0.034, weight: .heavy)).tracking(h * 0.034 * 0.1).foregroundStyle(.white)
                    .padding(.horizontal, h * 0.024).padding(.vertical, h * 0.008).background(Color(hex: "#d32f2f"), in: RoundedRectangle(cornerRadius: h * 0.012))
                Text(title.isEmpty ? "Live stream" : title).font(.system(size: h * 0.08, weight: .heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("HLS feed plays here on the TV").font(.system(size: h * 0.03)).foregroundStyle(.white.opacity(0.7))
            }.padding(h * 0.06)
        case .ndi(let title, let source, let fit):
            NdiPlaceholderContent(title: title, source: source, fit: fit, width: w, height: h)
        case .blank:
            EmptyView()
        case .sign(let s):
            SignContent(item: s, width: w, height: h, portrait: shape == .portrait)
        default:
            if let plan = SlideRender.planText(frame, theme: theme) {
                TextBox(plan: plan, theme: theme, shape: shape, width: w, height: h)
            }
        }
    }

    /// Short text for VoiceOver.
    static func describe(_ f: PreviewFrame) -> String {
        switch f {
        case .text(_, let title, let body, _, _): return [title, body].filter { !$0.isEmpty }.joined(separator: ". ").nonEmpty ?? "Empty text slide"
        case .lyric(let text, let label, _, _): return (label.isEmpty ? "" : label + ": ") + text.replacingOccurrences(of: "\n", with: " ")
        case .songTitle(let title, _, _, _): return "Song title: \(title)"
        case .countdown(let title, _, _): return "Countdown \(title)"
        case .media(_, let kind, _): return kind == .video ? "Video" : kind == .audio ? "Audio" : "Image"
        case .stream(let title): return "Live stream \(title)"
        case .ndi(let title, let source, _): return "Experimental NDI source \(title.isEmpty ? source : title). No preview, the picture appears on the TV."
        case .blank: return "Blank screen"
        case .sign(let s): return "Sign: \(s.title)"
        }
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

// MARK: - Layers

private struct BackgroundLayer: View {
    let background: SlideBackground
    let live: Bool

    var body: some View {
        switch background.kind {
        case .color:
            Color(hex: background.color, fallback: Color(hex: SlideMetrics.defaultNavy))
        case .gradient:
            LinearGradient(colors: [Color(hex: background.color), Color(hex: background.color2)], startPoint: start, endPoint: end)
        case .image, .video, .unknown:
            ZStack {
                Color(hex: background.color ?? "#000000")
                if let url = background.url, !url.isEmpty {
                    if background.kind == .video, live, DemoMedia.parse(url) == nil, let u = URL(string: url) {
                        LoopingVideoView(url: u, fit: background.effectiveFit)
                    } else {
                        MediaThumbnail(url: url, kind: background.kind == .video ? .video : .image, fit: background.effectiveFit, showsBadge: false)
                    }
                }
            }
        }
    }

    /// CSS linear-gradient angles are clockwise from "up"; 135 runs top-left to bottom-right.
    private var start: UnitPoint { let a = vector; return UnitPoint(x: 0.5 - a.dx / 2, y: 0.5 - a.dy / 2) }
    private var end: UnitPoint { let a = vector; return UnitPoint(x: 0.5 + a.dx / 2, y: 0.5 + a.dy / 2) }
    private var vector: (dx: Double, dy: Double) {
        let r = background.effectiveAngle * .pi / 180
        return (sin(r), -cos(r))
    }
}

private struct LogoView: View {
    let url: URL; let position: LogoPosition; let width: Double; let height: Double
    var body: some View {
        let alignment: Alignment = switch position {
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        }
        RemoteImage(url: url, fit: .contain)
            .frame(maxWidth: width * 0.2, maxHeight: height * 0.09)
            .padding(.horizontal, width * 0.03).padding(.vertical, height * 0.04)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// The theme text of a frame: blocks sized in percent of the frame height, shrunk by `SlideRender.fitScale`, placed in the plan's box.
private struct TextBox: View {
    let plan: SlideRender.TextPlan
    let theme: ResolvedTheme
    let shape: FrameShape
    let width: Double
    let height: Double

    var body: some View {
        let k = SlideRender.fitScale(plan, theme: theme, shape: shape)
        let boxTop = height * plan.top / 100
        let boxHeight = height * (plan.bottom - plan.top) / 100
        let margin = width * theme.margin / 100
        VStack(alignment: plan.align == .left ? .leading : .center, spacing: 0) {
            ForEach(Array(plan.blocks.enumerated()), id: \.offset) { i, b in
                blockView(b, k: k)
                    .padding(.top, i == 0 ? 0 : height * (plan.blocks[i - 1].size * ((plan.blocks[i - 1].role == .title || plan.blocks[i - 1].role == .label) ? 0.3 : 0.15) * k) / 100)
            }
        }
        .frame(width: width - 2 * margin, alignment: plan.align == .left ? .leading : .center)
        .frame(height: boxHeight, alignment: .center)
        .clipped()
        .position(x: width / 2, y: boxTop + boxHeight / 2)
    }

    private func font(_ b: SlideRender.Block, k: Double) -> Font {
        let size = height * b.size * k / 100
        let weight: Font.Weight = b.weight >= 800 ? .heavy : b.weight >= 700 ? .bold : b.weight >= 600 ? .semibold : b.weight >= 500 ? .medium : .regular
        let f = Font.system(size: size, weight: weight, design: theme.font == .julius ? .rounded : .default)
        return b.role == .time ? f.monospacedDigit() : f
    }

    private func styled(_ b: SlideRender.Block, k: Double) -> Text {
        let size = height * b.size * k / 100
        var t = Text(b.role == .label ? b.text.uppercased() : b.text).font(font(b, k: k)).foregroundColor(Color(hex: plan.color, fallback: .white))
        if b.role == .label { t = t.tracking(size * 0.14) }
        else if theme.font == .julius && b.role == .title { t = t.tracking(size * 0.03) }
        return t
    }

    private func blockView(_ b: SlideRender.Block, k: Double) -> some View {
        styled(b, k: k)
            .multilineTextAlignment(plan.align == .left ? .leading : .center)
            .opacity(b.role == .label ? 0.75 : b.role == .small ? 0.85 : 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: plan.align == .left ? .leading : .center)
            .modifier(TextEffects(shadow: theme.shadow, outline: theme.outline, height: height))
    }
}

private struct TextEffects: ViewModifier {
    let shadow: Bool; let outline: Bool; let height: Double
    func body(content: Content) -> some View {
        let o = height * 0.003
        content
            // SwiftUI has no text stroke: four hard black copies around the text read as an outline.
            .shadow(color: outline ? .black : .clear, radius: 0, x: o, y: 0)
            .shadow(color: outline ? .black : .clear, radius: 0, x: -o, y: 0)
            .shadow(color: outline ? .black : .clear, radius: 0, x: 0, y: o)
            .shadow(color: outline ? .black : .clear, radius: 0, x: 0, y: -o)
            .shadow(color: shadow ? .black.opacity(0.75) : .clear, radius: height * 0.011, x: 0, y: height * 0.0035)
    }
}

/// A Signage text sign, laid out like the website's sign mock-up (sizes in percent of the frame WIDTH, longer titles shrink).
private struct SignContent: View {
    let item: SignItem; let width: Double; let height: Double; let portrait: Bool

    private func titleSize(_ len: Int) -> Double {
        let base = len <= 12 ? 12.0 : len <= 24 ? 9.0 : len <= 48 ? 6.5 : 4.8
        return portrait ? base * 0.78 : base
    }

    var body: some View {
        let color = Color(hex: ColorTools.signTextColor(item.background))
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = title.isEmpty ? "Your title here" : title
        let size = width * titleSize(shown.count) / 100
        VStack(alignment: item.align == .left ? .leading : .center, spacing: size * 0.3) {
            Text(shown).font(.system(size: size, weight: .heavy)).foregroundColor(color).opacity(title.isEmpty ? 0.5 : 1)
            if !item.subtext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.subtext).font(.system(size: size * 0.45, weight: .medium)).foregroundColor(color)
            }
        }
        .multilineTextAlignment(item.align == .left ? .leading : .center)
        .padding(width * 0.07)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.align == .left ? .leading : .center)
        .overlay(alignment: .topLeading) {
            if item.logo {
                Image(systemName: "building.columns.fill").font(.system(size: height * 0.07)).foregroundColor(color.opacity(0.7))
                    .padding(width * 0.03).accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Convenience wrappers

/// A deck slide in both frames (16:9 and 9:16) with a stepper for slides that make several screens (a song: title, then each lyric slide).
/// This is what the deck editor shows for the selected slide.
struct SlidePreviewCard: View {
    var slide: DeckSlide
    var deckBackground: SlideBackground?
    var theme: ThemeConfig?
    var songs: SongLookup
    var defaultColor: String = SlideMetrics.defaultNavy
    var logoURL: URL?
    var live = true
    @State private var index = 0

    var body: some View {
        let frames = SlideRender.frames(for: slide, songs: songs)
        let i = min(index, frames.count - 1)
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(spacing: 4) {
                    SlidePreview(slide: slide, frameIndex: i, deckBackground: deckBackground, theme: theme, songs: songs, defaultColor: defaultColor, shape: .landscape, logoURL: logoURL, live: live)
                    Text("Landscape 16:9").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    SlidePreview(slide: slide, frameIndex: i, deckBackground: deckBackground, theme: theme, songs: songs, defaultColor: defaultColor, shape: .portrait, logoURL: logoURL, live: live)
                    Text("Portrait 9:16").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(maxWidth: 150)
            }
            if frames.count > 1 {
                HStack {
                    Button { index = max(0, i - 1) } label: { Label("Back", systemImage: "chevron.left") }.disabled(i == 0)
                    Spacer()
                    Text("Screen \(i + 1) of \(frames.count)").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button { index = min(frames.count - 1, i + 1) } label: { Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon) }.disabled(i == frames.count - 1)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .onChange(of: slide.id) { _, _ in index = 0 }
    }
}

/// A Kids or Signage playlist item as the TV shows it (first screen; `frameIndex` picks the others for lyrics).
/// Signs draw like the website's sign mock-up, everything else uses the default look: church colour, white text.
struct PlaylistItemPreview: View {
    var item: PlaylistItem
    var frameIndex = 0
    var songs: SongLookup = [:]
    var defaultColor: String = SlideMetrics.defaultNavy
    var shape: FrameShape = .landscape
    var logoURL: URL?
    var live = false

    var body: some View {
        let frames = SlideRender.frames(for: item, songs: songs)
        SlidePreview(frame: frames[min(max(0, frameIndex), frames.count - 1)], theme: ResolvedTheme(),
                     background: .solid(defaultColor), shape: shape, logoURL: logoURL, live: live)
    }
}
