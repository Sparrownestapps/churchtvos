import SwiftUI
import ChurchTVCore

/// The editor for one playlist item: live preview on top, then the form for its type. Pushed from the playlist editor.
/// Every form edits `item.content` in place so keys the app does not know (kept in each payload's `extra`) are written back.
struct PlaylistItemEditorView: View {
    @Environment(AppModel.self) private var model
    let kind: PlaylistKind
    @Binding var item: PlaylistItem
    var branding: OrgBranding?
    var defaultColor: String

    private var typeTitle: String {
        item.typeName.map { PlaylistEditorLabels.menuLabel($0, kind: kind) } ?? "Item"
    }

    var body: some View {
        Form {
            ItemPreviewSection(item: item, kind: kind, songs: model.content.songLookup, branding: branding, defaultColor: defaultColor)
            switch item.content {
            case .video(let c): MediaItemForm(kind: kind, isImage: false, clip: clipBinding(c))
            case .image(let c): MediaItemForm(kind: kind, isImage: true, clip: clipBinding(c))
            case .countdown: CountdownFieldsView(settings: countdownBinding, module: kind.module)
            case .lyrics: LyricsForm(lyrics: lyricsBinding)
            case .youtube: YouTubeForm(item: youtubeBinding, branding: branding)
            case .sign: SignForm(sign: signBinding, branding: branding)
            case .stream: StreamForm(kind: kind, stream: streamBinding)
            case .unknown(let u): UnknownItemSection(item: u)
            }
            if let problem = item.problem, !isCountdown {
                Section { Label(problem.prefix(1).uppercased() + problem.dropFirst(), systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange) }
            }
        }
        .navigationTitle(typeTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isCountdown: Bool { if case .countdown = item.content { return true }; return false }

    // MARK: Bindings into the typed content

    private func clipBinding(_ initial: MediaClip) -> Binding<MediaClip> {
        Binding(get: {
            switch item.content { case .video(let c), .image(let c): return c; default: return initial }
        }, set: { new in
            switch item.content { case .video: item.content = .video(new); case .image: item.content = .image(new); default: break }
        })
    }
    private var countdownBinding: Binding<CountdownSettings> {
        Binding(get: { if case .countdown(let c) = item.content { return c.countdown }; return .new },
                set: { new in if case .countdown(var c) = item.content { c.countdown = new; item.content = .countdown(c) } })
    }
    private var lyricsBinding: Binding<LyricsItem> {
        Binding(get: { if case .lyrics(let l) = item.content { return l }; return LyricsItem() },
                set: { item.content = .lyrics($0) })
    }
    private var youtubeBinding: Binding<YouTubeItem> {
        Binding(get: { if case .youtube(let y) = item.content { return y }; return YouTubeItem() },
                set: { item.content = .youtube($0) })
    }
    private var signBinding: Binding<SignItem> {
        Binding(get: { if case .sign(let s) = item.content { return s }; return SignItem() },
                set: { item.content = .sign($0) })
    }
    private var streamBinding: Binding<StreamItem> {
        Binding(get: { if case .stream(let s) = item.content { return s }; return StreamItem() },
                set: { item.content = .stream($0) })
    }
}

// MARK: - Preview

/// What the TV will show: lyrics step through their screens; signs show both landscape and portrait.
private struct ItemPreviewSection: View {
    let item: PlaylistItem
    let kind: PlaylistKind
    let songs: SongLookup
    var branding: OrgBranding?
    var defaultColor: String
    @State private var index = 0

    private var frameCount: Int { SlideRender.frames(for: item, songs: songs).count }

    private func logoURL(_ item: PlaylistItem) -> URL? {
        guard case .sign(let s) = item.content, s.logo else { return nil }
        return branding?.logo(forBackground: s.background).flatMap(URL.init(string:))
    }

    var body: some View {
        Section {
            VStack(spacing: 8) {
                if case .sign = item.content {
                    HStack(alignment: .bottom, spacing: 14) {
                        shape(.landscape, "Landscape 16:9").frame(maxWidth: .infinity)
                        shape(.portrait, "Portrait 9:16").frame(maxWidth: 130)
                    }
                } else {
                    PlaylistItemPreview(item: item, frameIndex: min(index, max(0, frameCount - 1)), songs: songs, defaultColor: defaultColor, live: true)
                        .frame(maxWidth: 460)
                        .accessibilityHidden(true)
                }
                if frameCount > 1 {
                    HStack {
                        Button { index = max(0, index - 1) } label: { Label("Back", systemImage: "chevron.left") }.disabled(index == 0)
                        Spacer()
                        Text("Screen \(min(index, frameCount - 1) + 1) of \(frameCount)").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button { index = min(frameCount - 1, index + 1) } label: { Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon) }.disabled(index >= frameCount - 1)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
        } header: { Text("Preview") }
    }

    private func shape(_ shape: FrameShape, _ caption: String) -> some View {
        VStack(spacing: 4) {
            PlaylistItemPreview(item: item, songs: songs, defaultColor: defaultColor, shape: shape, logoURL: logoURL(item))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) preview of the sign")
    }
}

// MARK: - Seconds field

/// A number of seconds: a text field you can type in plus a stepper for small changes.
struct SecondsRow: View {
    var title: String
    @Binding var seconds: Int
    var range: ClosedRange<Int> = 1...3600
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 64)
                .focused($focused)
                .accessibilityLabel(title)
            Text("s").foregroundStyle(.secondary)
            Stepper("", value: Binding(get: { seconds }, set: { seconds = $0; text = "\($0)" }), in: range, step: 1).labelsHidden()
        }
        .onAppear { text = "\(seconds)" }
        .onChange(of: seconds) { _, new in if !focused { text = "\(new)" } }
        .onChange(of: text) { _, new in
            let digits = new.filter(\.isNumber)
            if digits != new { text = digits; return }
            if let v = Int(digits), v >= range.lowerBound { seconds = min(range.upperBound, v) }
        }
        .onChange(of: focused) { _, f in if !f { text = "\(seconds)" } }
    }
}

// MARK: - Picture / video

private struct MediaItemForm: View {
    @Environment(AppModel.self) private var model
    let kind: PlaylistKind
    let isImage: Bool
    @Binding var clip: MediaClip
    @State private var picking = false

    private var mediaKind: MediaKind { isImage ? .image : .video }
    private var noun: String { isImage ? (kind == .kids ? "picture" : "image") : "video" }
    private var chosenTitle: String { clip.title.isEmpty ? (URL(string: clip.url)?.lastPathComponent ?? "File") : clip.title }
    /// Kids pictures may wait for Next (nil seconds); Signage pictures always have a time.
    private var waitsForNext: Bool { kind == .kids && clip.seconds == nil }

    var body: some View {
        Section {
            Button { picking = true } label: {
                HStack(spacing: 12) {
                    if clip.url.isEmpty {
                        Image(systemName: mediaKind.symbol).frame(width: 64, height: 40).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                        Text("Choose a \(noun) from the library").foregroundStyle(.tint)
                    } else {
                        MediaThumbnail(url: clip.url, kind: mediaKind).frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chosenTitle).foregroundStyle(.primary).lineLimit(2)
                            Text("Change \(noun)…").font(.caption).foregroundStyle(.tint)
                        }
                    }
                    Spacer()
                }
            }
            .accessibilityLabel(clip.url.isEmpty ? "Choose a \(noun) from the library" : "\(noun.capitalized): \(chosenTitle). Change")
        } header: { Text(isImage ? (kind == .kids ? "Picture" : "Image") : "Video") } footer: {
            Text("From the \(kind.module.displayName) library. Use portrait media (1080 x 1920) for screens turned to portrait.")
        }

        if isImage {
            Section {
                if kind == .kids {
                    Toggle("Go to the next item automatically", isOn: Binding(get: { !waitsForNext }, set: { clip.seconds = $0 ? (clip.seconds ?? 10) : nil }))
                }
                if !waitsForNext {
                    SecondsRow(title: kind == .kids ? "Auto-advance after" : "Show for", seconds: Binding(get: { clip.seconds ?? 10 }, set: { clip.seconds = $0 }))
                }
            } header: { Text("Timing") } footer: {
                Text(kind == .kids
                     ? (waitsForNext ? "The picture stays up until the volunteer presses Next on the remote." : "Moves on by itself after this many seconds.")
                     : "How long this image stays on the screen before the next item.")
            }
        } else {
            Section { Label("Plays to the end", systemImage: "play.circle") .foregroundStyle(.secondary) } header: { Text("Timing") }
        }

        Section {
            TextField("Title (optional)", text: $clip.title)
        } header: { Text("Name in the list") }
        .sheet(isPresented: $picking) {
            MediaPickerView(module: kind.module, kinds: [mediaKind], title: "Choose a \(noun)", selectedId: clip.mediaId) { m in clip.apply(m) }
        }
    }
}

// MARK: - Lyrics

private struct TypedSlideRow: Identifiable, Equatable { let id = UUID(); var text: String }

private struct LyricsForm: View {
    @Environment(AppModel.self) private var model
    @Binding var lyrics: LyricsItem
    @State private var stash: LyricsStash
    @State private var picking = false

    init(lyrics: Binding<LyricsItem>) {
        _lyrics = lyrics
        _stash = State(initialValue: LyricsStash(lyrics.wrappedValue))
    }

    private var song: Song? { lyrics.songId.flatMap { model.content.songLookup[$0.lowercased()] } }

    var body: some View {
        Section {
            Picker("Where the words come from", selection: Binding(get: { lyrics.isLibrary }, set: { lyrics = stash.switched(lyrics, toLibrary: $0) })) {
                Text("From song library").tag(true)
                Text("Typed lyrics").tag(false)
            }
            .pickerStyle(.segmented)
        } header: { Text("Source") }

        if lyrics.isLibrary { librarySection } else { TypedLyricsSections(lyrics: $lyrics) }

        Section {
            Toggle("Show song title first", isOn: Binding(get: { lyrics.showTitle ?? false }, set: { lyrics.showTitle = $0 }))
        } footer: {
            Text("Shows the song name as its own slide before the words. It stays up until you press Next.\n\nStyled title slide needs app version 1.3.0 or newer; older TVs show a plain first slide.")
        }
    }

    @ViewBuilder private var librarySection: some View {
        Section {
            Button { picking = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lyrics.songId == nil || (lyrics.songId ?? "").isEmpty ? "Choose a song…" : (song?.title ?? (lyrics.title.isEmpty ? "Song not in the library" : lyrics.title)))
                            .foregroundStyle(song == nil ? Color.accentColor : Color.primary)
                        if let song {
                            let n = SongExpander.expand(song).count
                            Text("\(n) \(n == 1 ? "slide" : "slides") · the playlist uses the latest version of the song").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            if let id = lyrics.songId, !id.isEmpty, song == nil, model.content.supportLoaded {
                Label("This song isn't in the library any more, so the TV will skip this item. Choose another song.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if model.content.supportLoaded && model.content.songs.isEmpty {
                Label("There are no songs yet. Add some on the Songs page of the website, then come back.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("Song") }
        .sheet(isPresented: $picking) {
            SongPickerView(selectedId: lyrics.songId) { s in
                lyrics.songId = s.id.uuidString.lowercased(); lyrics.title = s.title
            }
        }
    }
}

/// Typed lyrics: the song title and a list of slides (add, remove, reorder, several lines each).
private struct TypedLyricsSections: View {
    @Binding var lyrics: LyricsItem
    @State private var rows: [TypedSlideRow] = []
    @State private var loaded = false

    var body: some View {
        Section {
            TextField("Song title", text: $lyrics.title)
        } header: { Text("Song title") }

        Section {
            ForEach($rows) { $row in
                let n = (rows.firstIndex { $0.id == row.id } ?? 0) + 1
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slide \(n)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextEditor(text: $row.text).frame(minHeight: 96)
                        .accessibilityLabel("Lyrics for slide \(n)")
                }
                .swipeActions { Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: { Label("Delete", systemImage: "trash") } }
                .accessibilityAction(named: "Move up") { move(row.id, by: -1) }
                .accessibilityAction(named: "Move down") { move(row.id, by: 1) }
            }
            .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { rows.remove(atOffsets: $0) }
            Button { rows.append(TypedSlideRow(text: "")); Haptics.selection() } label: { Label("Add slide", systemImage: "plus.circle.fill") }
        } header: {
            HStack {
                Text("Lyrics slides")
                Spacer()
                if rows.count > 1 { EditButton().font(.subheadline.weight(.medium)).textCase(nil) }
            }
        } footer: {
            Text("\(TypedLyrics.savedCount(rows.map(\.text))) \(TypedLyrics.savedCount(rows.map(\.text)) == 1 ? "slide" : "slides"). Each slide is one screen on the TV. Blank slides are dropped when you save.")
        }
        .onAppear { if !loaded { rows = lyrics.slides.map { TypedSlideRow(text: $0) }; loaded = true } }
        .onChange(of: rows) { _, new in
            let texts = new.map(\.text)
            if texts != lyrics.slides { lyrics.slides = texts }
        }
        .onChange(of: lyrics.slides) { _, new in
            if new != rows.map(\.text) { rows = new.map { TypedSlideRow(text: $0) } }
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(i + delta) else { return }
        rows.swapAt(i, i + delta)
    }
}

// MARK: - YouTube

private struct YouTubeForm: View {
    @Environment(AppModel.self) private var model
    @Binding var item: YouTubeItem
    var branding: OrgBranding?
    @State private var link = ""
    @State private var linkError: String?
    @State private var fetching = false
    @State private var startText = ""

    private var channel: String? { branding?.youtubeChannelId ?? item.channelId }
    private var live: Bool { (item.videoId ?? "").isEmpty && !(item.channelId ?? "").isEmpty }
    private var churchName: String { model.church?.organization.name ?? "Church" }

    var body: some View {
        Group { sections }
            .onAppear { startText = YouTubeLink.startText(item.start) }
            .onDisappear(perform: commitStart)
    }

    @ViewBuilder private var sections: some View {
        Section {
            Picker("Kind", selection: Binding(get: { live }, set: { setLive($0) })) {
                Text("Live now").tag(true)
                Text("Choose a video").tag(false)
            }
            .pickerStyle(.segmented)
            if branding?.youtubeChannelId == nil && !live {
                Text("Add your church's YouTube channel in Settings on the website to use Live now.").font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("What to play") }

        if live {
            Section {
                Text("Plays whatever \(churchName) is live-streaming on YouTube when this item comes up. If nothing is live, the TV says so and the volunteer can skip it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Name in the list") { TextField("Title", text: $item.title) }
        } else {
            if let id = item.videoId, !id.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        AsyncImage(url: YouTubeLink.thumbnail(id)) { phase in
                            if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color(.tertiarySystemFill) }
                        }
                        .frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title.isEmpty ? "YouTube video" : item.title).lineLimit(2)
                            if let url = URL(string: "https://youtu.be/\(id)") { Link("Preview on YouTube", destination: url).font(.caption) }
                        }
                    }
                } header: { Text("Chosen video") }
            }
            Section {
                TextField("https://www.youtube.com/watch?v=…", text: $link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go).onSubmit { Task { await useLink() } }
                    .accessibilityLabel("YouTube link or video id")
                Button { Task { await useLink() } } label: {
                    if fetching { HStack { ProgressView(); Text("Checking…") } } else { Text(item.videoId == nil ? "Use link" : "Use this link instead") }
                }
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || fetching)
                if let linkError { Label(linkError, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange) }
            } header: { Text("Paste any YouTube link or video id") } footer: {
                Text("Watch, youtu.be, live, embed and Shorts links all work. YouTube items don't rotate on portrait screens.")
            }
            Section {
                TextField("e.g. 12:30", text: $startText)
                    .keyboardType(.numbersAndPunctuation)
                    .onSubmit(commitStart)
                    .accessibilityLabel("Start at, minutes and seconds")
                TextField("Title", text: $item.title)
            } header: { Text("Options") } footer: { Text("Start at is optional. The title is only for the list.") }
        }
    }

    private func commitStart() {
        let start = YouTubeLink.parseStart(startText)
        if start != item.start { item.start = start }
        startText = YouTubeLink.startText(start)
    }

    private func setLive(_ on: Bool) {
        guard on != live else { return }
        if on {
            guard let channel = branding?.youtubeChannelId ?? item.channelId else { return }
            item.videoId = nil; item.channelId = channel; item.start = nil
            item.title = "\(churchName) · Live now"
        } else {
            item.videoId = nil; item.channelId = nil; item.title = ""
        }
        startText = ""
    }

    private func useLink() async {
        guard let id = YouTubeLink.parseId(link) else { linkError = "That doesn't look like a YouTube link."; return }
        linkError = nil
        fetching = true
        defer { fetching = false }
        let title = model.isDemo ? nil : await YouTubeTitle.fetch(id)
        item.videoId = id; item.channelId = nil; item.title = title ?? "YouTube video"
        link = ""
        Haptics.selection()
    }
}

/// The video's title from YouTube's public oEmbed endpoint (nil when offline or private).
enum YouTubeTitle {
    static func fetch(_ id: String) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/oembed?format=json&url=https://youtu.be/\(id)") else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let title = obj["title"] as? String, !title.isEmpty else { return nil }
        return title
    }
}

// MARK: - Sign

private struct SignForm: View {
    @Binding var sign: SignItem
    var branding: OrgBranding?

    private var swatches: [(name: String, hex: String)] {
        var out: [(String, String)] = []
        if let p = branding?.primaryColor { out.append(("Church primary", p)) }
        if let a = branding?.accentColor { out.append(("Church accent", a)) }
        return out
    }

    var body: some View {
        Section {
            TextField("e.g. Welcome! Services at 9 and 11", text: $sign.title, axis: .vertical).lineLimit(1...3)
                .accessibilityLabel("Title")
            TextField("Smaller text (optional), e.g. Coffee is in the lobby", text: $sign.subtext, axis: .vertical).lineLimit(1...4)
                .accessibilityLabel("Smaller text")
        } header: { Text("Text") }

        Section {
            ColorRow(title: "Background", hex: $sign.background, extra: swatches)
            Picker("Alignment", selection: $sign.align) {
                Text("Centre").tag(SlideAlign.center)
                Text("Left").tag(SlideAlign.left)
            }
            .pickerStyle(.segmented)
        } header: { Text("Look") }

        Section {
            SecondsRow(title: "Show for", seconds: $sign.seconds)
            Toggle("Show church logo", isOn: $sign.logo)
            if sign.logo && branding?.logo(forBackground: sign.background) == nil {
                Label("No logo has been added yet. Add one under Settings on the website.", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("Timing") }

        Section { Label(StreamNotes.needsApp, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
    }
}

enum StreamNotes {
    static let needsApp = "Needs the Church TV OS app version 1.1.0 or newer on the TV."
}

// MARK: - Live stream

private struct StreamForm: View {
    let kind: PlaylistKind
    @Binding var stream: StreamItem
    @State private var testing = false
    @State private var result: StreamLink.TestResult?

    var body: some View {
        Section {
            TextField("e.g. Sunday service live", text: $stream.title).accessibilityLabel("Title")
        } header: { Text("Title") }

        Section {
            TextField("https://…/playlist.m3u8", text: Binding(get: { stream.url }, set: { stream.url = $0; result = nil }), axis: .vertical)
                .lineLimit(1...4)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Stream link, HLS m3u8")
            if let hint = StreamLink.hint(stream.url) {
                Label(hint, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
            Button { Task { await test() } } label: {
                if testing { HStack { ProgressView(); Text("Testing…") } } else { Label("Test link", systemImage: "checkmark.seal") }
            }
            .disabled(testing || stream.url.trimmingCharacters(in: .whitespaces).isEmpty)
            if let result {
                Label(result.text, systemImage: result.isOK ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.footnote).foregroundStyle(result.isOK ? .green : .orange)
            }
        } header: { Text("Stream link (HLS, .m3u8)") } footer: { Text("The link must start with https://") }

        Section {
            Toggle(kind == .kids ? "Stop after a set time" : "Show for a set time", isOn: Binding(get: { stream.seconds != nil }, set: { stream.seconds = $0 ? (kind == .signage ? 30 : 60) : nil }))
            if stream.seconds != nil {
                SecondsRow(title: "Show for", seconds: Binding(get: { stream.seconds ?? 30 }, set: { stream.seconds = $0 }))
            }
            Picker("If the stream is down", selection: $stream.fallback) {
                Text("Skip it").tag(StreamFallback.skip)
                Text("Show \"waiting for feed\"").tag(StreamFallback.hold)
            }
            Toggle("Play sound", isOn: $stream.audio)
        } header: { Text("Playback") } footer: {
            Text("Leave the time off to keep the stream up until the next item is chosen (Kids) or the playlist loops past it (Signage). Skip it moves straight on if the stream isn't running, so a room is never left blank. Show \"waiting for feed\" holds a waiting card for a little while before moving on, which suits a stream that starts a few minutes late. Sound is off unless you turn it on.")
        }

        Section {
            DisclosureGroup("Using BoxCast?") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In BoxCast open the broadcast, choose Embed, and copy the Static M3U8 link into the box above.")
                    Text("BoxCast viewers are about 30 to 40 seconds behind real life, so don't use it for lyrics or anything that has to be in sync with the room.")
                    Text("For a near-live feed from the building, use a camera or switcher converted to HLS (for example with OBS or Nimble Streamer).")
                }
                .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 4)
            }
            Label(StreamNotes.needsApp, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func test() async {
        testing = true
        result = nil
        result = await StreamLink.test(stream.url)
        testing = false
    }
}

// MARK: - Unknown

private struct UnknownItemSection: View {
    let item: UnknownItem
    var body: some View {
        Section {
            Label("This item (\(item.typeName)) was made by a newer version of Church TV OS.", systemImage: "questionmark.square.dashed")
            Text("It is kept exactly as it is when you save. You can move or delete it from the playlist, but not edit it here.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
