import SwiftUI
import ChurchTVCore

/// The background chooser shared by slides, decks and themes (BackgroundPicker.tsx): Colour, Gradient, Image or Video from the
/// Slides library, fit and fill colour, the Dim slider, and "use the deck/theme background" (value nil) to clear.
///
/// `BackgroundPickerFields` contributes Form sections; `BackgroundLink` is a row that opens them on their own page.
struct BackgroundPickerFields: View {
    @Environment(ContentModel.self) private var model
    @Binding var value: SlideBackground?
    /// Text of the "no override" choice, for example "Use theme background".
    var inheritLabel: String
    var readOnly = false

    @State private var picking = false
    @State private var library: MediaLibrary?

    private var mode: BackgroundMode { BackgroundMode(value) }
    private var fileKind: MediaKind { value?.kind == .video ? .video : .image }

    var body: some View {
        Group {
            Section {
                Picker("Background type", selection: Binding(get: { mode }, set: { value = BackgroundEditing.switched(value, to: $0) })) {
                    ForEach(BackgroundMode.choices, id: \.self) { m in Text(m == .inherit ? inheritLabel : m.label).tag(m) }
                    if case .unknown = mode { Text(mode.label).tag(mode) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(readOnly)
            } header: { Text("Background type") }
            .sheet(isPresented: $picking) {
                MediaPickerView(module: .slides, kinds: [fileKind], title: fileKind == .video ? "Choose a video" : "Choose an image", selectedId: value?.mediaId) { item in
                    value?.mediaId = item.id.uuidString.lowercased()
                    value?.url = item.url
                    Task { library = try? await model.mediaLibrary(.slides, force: true) }
                }
            }
            .task { library = try? await model.mediaLibrary(.slides) }

            switch mode {
            case .color:
                Section("Colour") { ColorRow(title: "Colour", hex: bind(\.color, "#000000")) }
            case .gradient:
                Section("Gradient") {
                    ColorRow(title: "From", hex: bind(\.color, SlideMetrics.defaultNavy))
                    ColorRow(title: "To", hex: bind(\.color2, "#000000"))
                    VStack(alignment: .leading) {
                        Text("Angle: \(Int(value?.effectiveAngle ?? 135))°")
                        Slider(value: Binding(get: { value?.effectiveAngle ?? 135 }, set: { value?.angle = $0 }), in: 0...360, step: 5)
                            .accessibilityLabel("Gradient angle")
                            .accessibilityValue("\(Int(value?.effectiveAngle ?? 135)) degrees")
                    }
                }
            case .image, .video:
                fileSections
            case .unknown:
                Section { Label("This background type was made by a newer version. It is kept exactly as it is until you pick another type.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
            case .inherit:
                EmptyView()
            }

            if value != nil, mode != .inherit {
                Section {
                    VStack(alignment: .leading) {
                        Text("Dim: \(Int(((value?.effectiveDim ?? 0) * 100).rounded()))%")
                        Slider(value: Binding(get: { (value?.effectiveDim ?? 0) * 100 }, set: { value?.dim = BackgroundEditing.dimValue(percent: $0) }), in: 0...80, step: 5)
                            .accessibilityLabel("Dim")
                            .accessibilityValue("\(Int(((value?.effectiveDim ?? 0) * 100).rounded())) percent")
                    }
                } footer: { Text("A black layer over the background so the words stay readable.") }
            }
        }
    }

    @ViewBuilder private var fileSections: some View {
        let url = value?.url ?? ""
        let item = library?.item(id: value?.mediaId ?? "")
        Section(fileKind == .video ? "Video" : "Image") {
            HStack(spacing: 12) {
                Group {
                    if url.isEmpty {
                        RoundedRectangle(cornerRadius: 6).fill(Color.tertiaryFill).overlay { Text("None").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        MediaThumbnail(url: url, kind: fileKind).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(width: 84, height: 47)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.isEmpty ? "No \(fileKind == .video ? "video" : "image") chosen yet" : (item?.title ?? model.mediaTitle(forId: value?.mediaId ?? "") ?? "File from the library"))
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let item, let bytes = item.sizeBytes { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .accessibilityElement(children: .combine)
            if !readOnly {
                Button { picking = true } label: {
                    Label(url.isEmpty ? "Choose \(fileKind == .video ? "a video" : "an image") from the library…" : "Change \(fileKind == .video ? "video" : "image")…", systemImage: fileKind == .video ? "film" : "photo")
                }
            }
            if let item, MediaSize.isOversize(kind: item.kind, bytes: item.sizeBytes) {
                Label(MediaSize.warning, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
        }
        Section {
            Picker("Fit", selection: Binding(get: { value?.effectiveFit ?? .cover }, set: { value?.fit = $0 })) {
                Text("Fill the screen (crops the edges)").tag(ContentFit.cover)
                Text("Show it all (fill colour around it)").tag(ContentFit.contain)
            }
            .navigationLinkPicker()
            if value?.effectiveFit == .contain {
                ColorRow(title: "Fill colour", hex: bind(\.color, "#000000"))
            }
        } footer: {
            Text(fileKind == .video ? BackgroundEditing.videoGuidance : BackgroundEditing.imageGuidance)
        }
    }

    private func bind(_ kp: WritableKeyPath<SlideBackground, String?>, _ d: String) -> Binding<String> {
        Binding(get: { value?[keyPath: kp] ?? d }, set: { value?[keyPath: kp] = $0 })
    }
}

/// A row that shows the current background and opens `BackgroundPickerPage`.
struct BackgroundLink: View {
    var title = "Background"
    @Binding var value: SlideBackground?
    var inheritLabel: String
    var readOnly = false
    /// The look the background sits behind in the page's preview (the theme and the deck background above it).
    var previewTheme: ThemeConfig?
    var fallbackBackground: SlideBackground?

    var body: some View {
        NavigationLink {
            BackgroundPickerPage(value: $value, inheritLabel: inheritLabel, readOnly: readOnly, previewTheme: previewTheme, fallbackBackground: fallbackBackground)
        } label: {
            HStack(spacing: 12) {
                swatch.frame(width: 44, height: 25)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(BackgroundEditing.summary(value, inherit: inheritLabel)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the background picker")
    }

    @ViewBuilder private var swatch: some View {
        if let value, value.isUsable {
            SlidePreview(frame: .blank(color: "#000000"), background: value)
        } else {
            RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3])).foregroundStyle(.secondary)
        }
    }
}

/// The picker on its own page, with a live preview on top.
struct BackgroundPickerPage: View {
    @Binding var value: SlideBackground?
    var inheritLabel: String
    var readOnly = false
    var previewTheme: ThemeConfig?
    var fallbackBackground: SlideBackground?

    private var resolved: SlideBackground {
        BackgroundResolver.resolve(slide: value, deck: fallbackBackground, theme: previewTheme?.background)
    }

    var body: some View {
        Form {
            BackgroundPickerFields(value: $value, inheritLabel: inheritLabel, readOnly: readOnly)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SlidePreview(frame: .text(layout: .titleBody, title: "Welcome", body: "Words over this background", align: nil, color: nil),
                         theme: ResolvedTheme(previewTheme), background: resolved, live: true)
                .frame(maxWidth: 260)
                .padding(.vertical, 8).padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
        }
        .macReadableWidth()
        .navigationTitle("Background")
        .inlineNavigationTitle()
    }
}
