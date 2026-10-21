#if DEBUG
import SwiftUI
import ChurchTVCore

/// Developer gallery of the content UI kit, with demo data. Launch the app with `-demo -kitgallery` (optionally `-kitpage slides|items|controls`)
/// to see every preview kind in 16:9 and 9:16, the playlist item previews and the form controls. Debug builds only.
public struct KitGalleryView: View {
    public init() {}
    @Environment(ContentModel.self) private var model
    enum Page: String, CaseIterable { case slides, items, controls }
    @State private var page: Page = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "-kitpage"), i + 1 < a.count, let p = Page(rawValue: a[i + 1]) { return p }
        return .slides
    }()

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Page", selection: $page) { ForEach(Page.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    .pickerStyle(.segmented).padding()
                switch page {
                case .slides: SlidesPage()
                case .items: ItemsPage()
                case .controls: ControlsPage()
                }
            }
            .navigationTitle("UI kit")
            .inlineNavigationTitle()
            .task { await model.loadSupport(); await model.load(.slides); await model.load(.kids); await model.load(.signage) }
        }
    }

    // MARK: Slides

    private struct SlidesPage: View {
        @Environment(ContentModel.self) private var model
        var body: some View {
            ScrollView {
                let content = model
                let sunday = content.decks.first { $0.name.hasPrefix("Sunday") }
                let xmas = content.decks.first { $0.name.hasPrefix("Christmas") }
                VStack(alignment: .leading, spacing: 18) {
                    if let sunday {
                        let theme = content.theme(id: sunday.themeId)?.config
                        Text("Sunday deck, classic theme").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(sunday.slides.prefix(10)) { s in
                                VStack(alignment: .leading, spacing: 3) {
                                    SlidePreview(slide: s, deckBackground: sunday.background, theme: theme, songs: content.songLookup)
                                    Text(s.kind?.name ?? "Unknown").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("Song slide: every screen").font(.headline)
                        if let song = sunday.slides.first(where: { $0.kind == .song }) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                ForEach(0..<SlideRender.frames(for: song, songs: content.songLookup).count, id: \.self) { i in
                                    SlidePreview(slide: song, frameIndex: i, theme: theme, songs: content.songLookup)
                                }
                            }
                        }
                        Text("Slide preview card (both frames, stepper)").font(.headline)
                        if let song = sunday.slides.first(where: { $0.kind == .song }) {
                            SlidePreviewCard(slide: song, deckBackground: nil, theme: theme, songs: content.songLookup, live: false)
                        }
                    }
                    if let xmas {
                        let theme = content.theme(id: xmas.themeId)?.config
                        Text("Christmas deck: gradient deck background, warm theme, clock countdown").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(xmas.slides) { s in
                                SlidePreview(slide: s, deckBackground: xmas.background, theme: theme, songs: content.songLookup)
                            }
                        }
                    }
                    Text("Theme variants (same text)").font(.headline)
                    let sample = PreviewFrame.text(layout: .titleBody, title: "Welcome to church", body: "We're glad you're here. Service starts at 10:00 and everyone is welcome to stay for coffee afterwards.", align: nil, color: nil)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(content.themes) { t in
                            SlidePreview(frame: sample, theme: t.config.resolved, background: BackgroundResolver.resolve(slide: nil, deck: nil, theme: t.config.background))
                        }
                        SlidePreview(frame: sample, theme: ThemeConfig(titleScale: 1.3, textColor: "#f59e0b", align: .left, position: .lower, shadow: false, outline: true, margin: 14).resolved,
                                     background: .gradient("#101820", "#7c3aed", angle: 200, dim: 0.2))
                        SlidePreview(frame: sample, theme: ThemeConfig(position: .top).resolved, background: .solid("#1f3a5f"), shape: .portrait)
                            .frame(maxHeight: 150)
                    }
                    Text("Long lyric (auto-fit)").font(.headline)
                    let long = PreviewFrame.lyric(text: "Amazing grace, how sweet the sound\nThat saved a wretch like me\nI once was lost, but now am found\nWas blind, but now I see\nTwas grace that taught my heart to fear\nAnd grace my fears relieved", label: "Verse 1", n: 1, count: 4)
                    HStack {
                        SlidePreview(frame: long, theme: ThemeConfig().resolved, background: .solid("#1f3a5f"))
                        SlidePreview(frame: long, theme: ThemeConfig().resolved, background: .solid("#1f3a5f"), shape: .portrait).frame(maxWidth: 90)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Playlist items

    private struct ItemsPage: View {
        @Environment(ContentModel.self) private var model
        var body: some View {
            ScrollView {
                let content = model
                VStack(alignment: .leading, spacing: 14) {
                    ForEach([PlaylistKind.kids, .signage]) { kind in
                        ForEach(content.playlists(kind)) { p in
                            Text("\(kind.title): \(p.name)").font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                                ForEach(p.items) { item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        PlaylistItemPreview(item: item, songs: content.songLookup)
                                        Text(item.typeName?.label ?? "Unknown").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Text("Sign, portrait").font(.headline)
                    HStack {
                        PlaylistItemPreview(item: PlaylistItem(.sign(SignItem(title: "Welcome home! Services at 9 and 11", subtext: "Coffee in the lobby", background: "#f3efe6", align: .left))), shape: .portrait).frame(maxWidth: 90)
                        PlaylistItemPreview(item: PlaylistItem(.sign(SignItem(title: "", background: "#b3261e"))), shape: .portrait).frame(maxWidth: 90)
                        PlaylistItemPreview(item: PlaylistItem.newCountdown(), shape: .portrait).frame(maxWidth: 90)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Controls

    private struct ControlsPage: View {
        @Environment(ContentModel.self) private var model
        @State private var color = "#1f3a5f"
        @State private var countdown = CountdownSettings(title: "Service starts in", mode: .duration, seconds: 300,
                                                         audio: CountdownAudio(mediaId: "d0d0d0d0-0000-4000-8000-000300000007", url: DemoMedia.url(.audio, "6b7280", "374151")),
                                                         atZero: .hold, ifPassed: .zero)
        @State private var pickMedia = false
        @State private var pickSong = false
        @State private var picked = "Nothing chosen yet"
        var body: some View {
            Form {
                Section("Pickers") {
                    Button("MediaPickerView (images and video)") { pickMedia = true }
                    Button("SongPickerView") { pickSong = true }
                    Text(picked).font(.footnote).foregroundStyle(.secondary)
                }
                Section("ColorRow and ColorSwatches") {
                    ColorRow(title: "Background", hex: $color)
                }
                CountdownFieldsView(settings: $countdown, module: .slides)
            }
            .sheet(isPresented: $pickMedia) {
                MediaPickerView(module: .slides, kinds: [.image, .video]) { picked = "Media: \($0.title) (\($0.kind.label))" }
            }
            .sheet(isPresented: $pickSong) {
                SongPickerView { picked = "Song: \($0.title)" }
            }
        }
    }
}
#endif
