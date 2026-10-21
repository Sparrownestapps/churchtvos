import SwiftUI
import ChurchTVCore

// The per-kind slide forms of the deck editor (SlideEditors.tsx). Each contributes Form sections.

/// "Wait for Next" or "advance after N seconds".
struct AdvanceFields: View {
    var title = "Advance"
    @Binding var seconds: Int?

    var body: some View {
        Picker(title, selection: Binding(get: { seconds != nil }, set: { auto in seconds = auto ? (seconds ?? 10) : nil })) {
            Text("Wait for Next (remote)").tag(false)
            Text("Automatically after…").tag(true)
        }
        .navigationLinkPicker()
        if let s = seconds {
            Stepper(value: Binding(get: { s }, set: { seconds = DeckEditing.clampSeconds($0) }), in: 1...3600) {
                LabeledContent("Seconds", value: "\(s)")
            }
            .accessibilityLabel("Seconds")
            .accessibilityValue("\(s)")
        }
    }
}

/// The editor of the selected slide: its kind's fields, the background override and the private notes.
struct SlideFormSections: View {
    @Environment(ContentModel.self) private var model
    @Binding var slide: DeckSlide
    var deckBackground: SlideBackground?
    var theme: ThemeConfig?
    var readOnly = false

    var body: some View {
        Group {
            switch slide.content {
            case .text: TextSlideForm(content: textBinding)
            case .media(let m): MediaSlideForm(content: mediaBinding, current: m)
            case .song: SongSlideForm(content: songBinding)
            case .countdown: CountdownFieldsView(settings: countdownBinding, module: .slides)
            case .stream: StreamSlideForm(content: streamBinding)
            case .blank:
                Section("Screen colour") { ColorRow(title: "Colour", hex: Binding(get: { blankContent.color ?? "#000000" }, set: { slide.content = .blank(BlankSlideContent(color: $0)) })) }
            case .unknown(let kind):
                Section {
                    Label("This slide type\(kind.isEmpty ? "" : " (\(kind))") was made by a newer version of Church TV OS. It is kept exactly as it is. You can reorder or delete it here.", systemImage: "lock.fill")
                        .font(.subheadline)
                }
            }
            if DeckEditing.supportsBackground(slide) {
                Section {
                    BackgroundLink(title: "Background for this slide", value: $slide.background, inheritLabel: "Use deck/theme background", readOnly: readOnly,
                                   previewTheme: theme, fallbackBackground: deckBackground)
                }
            }
            if !isUnknown {
                Section {
                    TextField("Reminders for whoever runs the slides", text: Binding(get: { slide.notes ?? "" }, set: { slide.notes = $0 }), axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityLabel("Private notes")
                } header: { Text("Private notes") } footer: { Text("Never shown on the TV.") }
            }
        }
        .disabled(readOnly)
    }

    private var isUnknown: Bool { if case .unknown = slide.content { return true }; return false }

    private var textBinding: Binding<TextSlideContent> {
        Binding(get: { if case .text(let t) = slide.content { return t }; return TextSlideContent() }, set: { slide.content = .text($0) })
    }
    private var mediaBinding: Binding<MediaSlideContent> {
        Binding(get: { if case .media(let m) = slide.content { return m }; return MediaSlideContent() }, set: { slide.content = .media($0) })
    }
    private var songBinding: Binding<SongSlideContent> {
        Binding(get: { if case .song(let s) = slide.content { return s }; return SongSlideContent() }, set: { slide.content = .song($0) })
    }
    private var countdownBinding: Binding<CountdownSettings> {
        Binding(get: { if case .countdown(let c) = slide.content { return c }; return .new }, set: { slide.content = .countdown($0) })
    }
    private var streamBinding: Binding<StreamSlideContent> {
        Binding(get: { if case .stream(let s) = slide.content { return s }; return StreamSlideContent() }, set: { slide.content = .stream($0) })
    }
    private var blankContent: BlankSlideContent { if case .blank(let b) = slide.content { return b }; return BlankSlideContent() }
}

// MARK: - Text

private struct TextSlideForm: View {
    @Binding var content: TextSlideContent
    private var layout: SlideLayout { content.layout ?? .titleBody }

    var body: some View {
        Section("Words") {
            if layout != .body {
                TextField("Title, for example Welcome", text: Binding(get: { content.title ?? "" }, set: { content.title = $0 }), axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityLabel("Title")
            }
            if layout != .title {
                TextField("Words under the title", text: Binding(get: { content.body ?? "" }, set: { content.body = $0 }), axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel("Text")
            }
        }
        Section("Look") {
            Picker("Layout", selection: Binding(get: { layout }, set: { content.layout = $0 })) {
                Text("Title and text").tag(SlideLayout.titleBody)
                Text("Title only").tag(SlideLayout.title)
                Text("Text only").tag(SlideLayout.body)
                Text("Lower third (small caption)").tag(SlideLayout.lowerThird)
            }
            Picker("Align", selection: Binding(get: { content.align }, set: { content.align = $0 })) {
                Text("Use the theme").tag(SlideAlign?.none)
                Text("Centre").tag(SlideAlign?.some(.center))
                Text("Left").tag(SlideAlign?.some(.left))
            }
            OptionalColorRow(title: "Text colour", hex: $content.textColor, defaultHex: "#FFFFFF")
        }
        Section("Timing") { AdvanceFields(seconds: $content.seconds) }
    }
}

// MARK: - Media

private struct MediaSlideForm: View {
    @Environment(ContentModel.self) private var model
    @Binding var content: MediaSlideContent
    let current: MediaSlideContent
    @State private var picking = false
    @State private var library: MediaLibrary?

    var body: some View {
        let item = library?.item(id: content.mediaId)
        Section("File") {
            HStack(spacing: 12) {
                Group {
                    if content.url.isEmpty {
                        RoundedRectangle(cornerRadius: 6).fill(Color.tertiaryFill).overlay { Text("None").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        MediaThumbnail(url: content.url, kind: content.mediaKind == .video ? .video : .image).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(width: 96, height: 54)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.url.isEmpty ? "No file chosen yet" : (item?.title ?? model.mediaTitle(forId: content.mediaId) ?? "File from the library"))
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let bytes = item?.sizeBytes { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .accessibilityElement(children: .combine)
            Button { picking = true } label: {
                Label(content.url.isEmpty ? "Choose an image or video…" : "Change file…", systemImage: "photo.on.rectangle")
            }
            if let item, MediaSize.isOversize(kind: item.kind, bytes: item.sizeBytes) {
                Label(MediaSize.warning, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
        }
        Section("Look") {
            Picker("Fit", selection: Binding(get: { content.fit ?? .contain }, set: { content.fit = $0 })) {
                Text("Show it all").tag(ContentFit.contain)
                Text("Fill the screen (crops the edges)").tag(ContentFit.cover)
            }
            .navigationLinkPicker()
        }
        Section {
            if content.mediaKind == .video {
                Toggle("Play the video's sound", isOn: Binding(get: { content.audio ?? true }, set: { content.audio = $0 }))
            } else {
                AdvanceFields(seconds: $content.seconds)
            }
        } header: { Text("Timing") } footer: {
            if content.mediaKind == .video { Text("A video moves on by itself when it ends.") }
        }
        .sheet(isPresented: $picking) {
            MediaPickerView(module: .slides, kinds: [.image, .video], title: "Choose an image or video", selectedId: content.mediaId) { m in
                content.apply(m)
                if content.audio == nil { content.audio = true }
                Task { library = try? await model.mediaLibrary(.slides, force: true) }
            }
        }
        .task { library = try? await model.mediaLibrary(.slides) }
    }
}

// MARK: - Song

private struct SongSlideForm: View {
    @Environment(ContentModel.self) private var model
    @Binding var content: SongSlideContent
    @State private var picking = false

    var body: some View {
        let song = model.songLookup[content.songId.lowercased()]
        Section("Song") {
            Button { picking = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song?.title ?? (content.songId.isEmpty ? "Choose a song…" : "Song removed")).font(.headline).foregroundStyle(song == nil ? Color.accentColor : .primary)
                        if let a = song?.authors, !a.isEmpty { Text(a).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .accessibilityHint("Opens the song library")
            if song != nil, let n = DeckEditing.songScreens(content, songs: model.songLookup) {
                Label("Makes \(n) \(n == 1 ? "screen" : "screens") on the TV\(content.showTitle == true ? " (including the title slide)" : "")", systemImage: "rectangle.stack")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !content.songId.isEmpty, song == nil, model.supportLoaded {
                Label("This song isn't in the library any more, so the TV will skip this slide. Choose another song.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if model.supportLoaded, model.songs.isEmpty {
                Text("There are no songs yet. Add some on the Songs page of the website, then come back.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section {
            Toggle("Show song title first", isOn: Binding(get: { content.showTitle ?? false }, set: { content.showTitle = $0 }))
        } footer: {
            Text("A styled title slide (with authors, copyright and CCLI number) before the words. It stays up until you press Next. The words use the theme's text style; the Songs page sets lines per slide. The deck always uses the latest version of the song.")
        }
        .sheet(isPresented: $picking) {
            SongPickerView(selectedId: content.songId) { song in content.songId = song.id.uuidString.lowercased() }
        }
    }
}

// MARK: - Stream

private struct StreamSlideForm: View {
    @Binding var content: StreamSlideContent
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        Section {
            Label("Needs the Church TV OS app version 1.4.0 or newer on the TV.", systemImage: "info.circle")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("Title, for example Sunday service live", text: Binding(get: { content.title ?? "" }, set: { content.title = $0 }))
                .accessibilityLabel("Title")
        }
        Section {
            TextField("https://…/playlist.m3u8", text: Binding(get: { content.url }, set: { content.url = $0; result = nil }), axis: .vertical)
                .plainTextInput().urlKeyboard()
                .accessibilityLabel("Stream link")
            Button { Task { await test() } } label: {
                if testing { HStack { ProgressView(); Text("Testing…") } } else { Label("Test link", systemImage: "checkmark.circle") }
            }
            .disabled(testing || content.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.footnote).foregroundStyle(result.ok ? .green : .orange)
            }
        } header: { Text("Stream link (HLS, .m3u8)") }
        Section("Playing") {
            AdvanceFields(title: "Show for", seconds: $content.seconds)
            Picker("If the stream is down", selection: Binding(get: { content.fallback ?? .skip }, set: { content.fallback = $0 })) {
                Text("Skip it").tag(StreamFallback.skip)
                Text("Show \"waiting for feed\"").tag(StreamFallback.hold)
            }
            .navigationLinkPicker()
            Toggle("Play sound", isOn: Binding(get: { content.audio ?? false }, set: { content.audio = $0 }))
        }
        Section {} footer: {
            Text("Sound is off unless you turn it on. BoxCast viewers run 30 to 40 seconds behind real life, so don't use a BoxCast link for anything that has to match the room.")
        }
    }

    private func test() async {
        let u = content.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DeckEditing.canTestStream(u), let url = URL(string: u) else {
            result = (false, "Paste a full link starting with https:// first."); return
        }
        testing = true; result = nil
        defer { testing = false }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
            let head = String(decoding: data.prefix(200), as: UTF8.self)
            result = DeckEditing.streamTestResult(status: status, body: head)
        } catch {
            result = (false, "Couldn't check this link from the phone. That's common (the server may block checks, or the stream isn't live yet) and doesn't mean it's broken. The TV may still play it.")
        }
    }
}
