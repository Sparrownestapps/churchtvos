import SwiftUI
import UIKit
import AVFoundation
import ChurchTVCore

// Small helpers shared by the content UI kit (Kit/*.swift). See "Build 2 architecture" in apple/README.md.

extension Color {
    /// '#RRGGBB' (or 'RRGGBB'); falls back to `fallback` when the text is not a colour.
    init(hex: String?, fallback: Color = .black) {
        guard let hex, let c = ColorTools.rgb(hex.hasPrefix("#") ? hex : "#" + hex) else { self = fallback; return }
        self = Color(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: 1)
    }

    /// '#rrggbb' (lowercase) of this colour in sRGB.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return ColorTools.hex(r: Int((r * 255).rounded()), g: Int((g * 255).rounded()), b: Int((b * 255).rounded()))
    }
}

extension MediaKind {
    var label: String { switch self { case .image: return "Image"; case .video: return "Video"; case .audio: return "Audio" } }
    var pluralLabel: String { switch self { case .image: return "Images"; case .video: return "Videos"; case .audio: return "Audio" } }
    var symbol: String { switch self { case .image: return "photo"; case .video: return "film"; case .audio: return "music.note" } }
}

/// A picture for a library file: the image itself, a poster frame for a video, a music icon for audio.
/// Demo files (`demo:` URLs) draw a gradient so the demo works offline.
struct MediaThumbnail: View {
    let url: String
    let kind: MediaKind
    var fit: ContentFit = .cover
    var showsBadge = true

    var body: some View {
        ZStack {
            content
            if showsBadge, kind != .image {
                Image(systemName: kind == .video ? "play.fill" : "music.note")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(5).background(.black.opacity(0.55), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .clipped()
    }

    @ViewBuilder private var content: some View {
        if let demo = DemoMedia.parse(url) {
            LinearGradient(colors: [Color(hex: demo.color1), Color(hex: demo.color2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if kind == .audio {
            ZStack { Color(.tertiarySystemFill); Image(systemName: "waveform").font(.title3).foregroundStyle(.secondary) }
        } else if kind == .video {
            VideoPoster(url: URL(string: url), fit: fit)
        } else {
            RemoteImage(url: URL(string: url), fit: fit)
        }
    }
}

/// AsyncImage with a placeholder and an error state.
struct RemoteImage: View {
    let url: URL?
    var fit: ContentFit = .cover
    var body: some View {
        if let demo = url.flatMap({ DemoMedia.parse($0.absoluteString) }) {
            LinearGradient(colors: [Color(hex: demo.color1), Color(hex: demo.color2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: fit == .cover ? .fill : .fit)
                case .failure: ZStack { Color(.tertiarySystemFill); Image(systemName: "photo").foregroundStyle(.secondary) }
                default: ZStack { Color(.tertiarySystemFill); ProgressView() }
                }
            }
        }
    }
}

/// First frame of a video (loaded once, cached in memory).
struct VideoPoster: View {
    let url: URL?
    var fit: ContentFit = .cover
    @State private var image: UIImage?
    private static let cache = NSCache<NSURL, UIImage>()

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: fit == .cover ? .fill : .fit) }
            else { Image(systemName: "film").foregroundStyle(.secondary) }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            if let result = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)) {
                let ui = UIImage(cgImage: result.image)
                Self.cache.setObject(ui, forKey: url as NSURL)
                image = ui
            }
        }
    }
}

/// Muted, looping video filling its frame (video backgrounds in `SlidePreview`).
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var fit: ContentFit = .cover

    func makeUIView(context: Context) -> PlayerContainer {
        let v = PlayerContainer()
        v.configure(url: url, fit: fit)
        return v
    }
    func updateUIView(_ v: PlayerContainer, context: Context) {
        v.layer(for: fit)
        if v.currentURL != url { v.configure(url: url, fit: fit) }
    }
    static func dismantleUIView(_ v: PlayerContainer, coordinator: ()) { v.stop() }

    final class PlayerContainer: UIView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private(set) var currentURL: URL?
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func configure(url: URL, fit: ContentFit) {
            stop()
            currentURL = url
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(playerItem: item)
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            playerLayer.player = queue
            self.layer(for: fit)
            queue.play()
        }
        func layer(for fit: ContentFit) { playerLayer.videoGravity = fit == .cover ? .resizeAspectFill : .resizeAspect }
        func stop() { player?.pause(); looper?.disableLooping(); player = nil; looper = nil; playerLayer.player = nil }
    }
}
