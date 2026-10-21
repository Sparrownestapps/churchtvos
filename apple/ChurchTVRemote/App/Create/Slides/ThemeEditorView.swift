import SwiftUI
import ChurchTVCore

/// Edits a theme (ThemesPage.tsx ThemeEditor). The row already exists (the Create list creates it with its name first); Save writes it
/// through `model.content.save(theme)`. Keys this app does not know stay in `ThemeConfig.extra` and are written back.
struct ThemeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    let theme: SlideTheme
    @State private var name: String
    @State private var cfg: ThemeConfig
    @State private var originalName: String
    @State private var originalCfg: ThemeConfig
    @State private var sample: ThemeEditing.Sample = .text
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDiscard = false
    @State private var pendingPreset: ThemePreset?

    init(theme: SlideTheme) {
        self.theme = theme
        let filled = ThemeEditing.filled(theme.config)
        _name = State(initialValue: theme.name)
        _originalName = State(initialValue: theme.name)
        _cfg = State(initialValue: filled)
        _originalCfg = State(initialValue: filled)
    }

    private var dirty: Bool { name != originalName || cfg != originalCfg }
    private var readOnly: Bool {
        guard let c = model.church else { return false }
        return !ContentPermissions.canEditContent(role: c.role, modules: c.modules, siteIds: c.siteIds, module: .slides, siteId: nil)
    }
    private var problem: String? { ThemeEditing.problem(name: name, config: cfg, others: model.content.themes, editing: theme.id) }
    private var canSave: Bool { !readOnly && !saving && dirty && problem == nil }
    private var wide: Bool { sizeClass == .regular }
    private var resolved: ResolvedTheme { cfg.resolved }
    private var background: SlideBackground { BackgroundResolver.resolve(slide: nil, deck: nil, theme: cfg.background) }

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    form
                    Divider()
                    ScrollView {
                        VStack(spacing: 12) { samplePicker; previews(landscapeMax: 400, portraitWidth: 130) }.padding()
                    }
                    .frame(width: 440)
                    .background(Color(.secondarySystemGroupedBackground))
                }
            } else {
                form.safeAreaInset(edge: .top, spacing: 0) {
                    previews(landscapeMax: 250, portraitWidth: 56)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
        .navigationTitle(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Theme" : name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(dirty ? "Cancel" : "Close") { if dirty { confirmDiscard = true } else { dismiss() } }
            }
            if !readOnly {
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(!canSave) }
            }
        }
        .confirmationDialog("You have unsaved changes.", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Leave without saving this theme?") }
        .confirmationDialog(pendingPreset.map { "Use “\($0.name)”?" } ?? "", isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }), titleVisibility: .visible) {
            Button("Replace the settings") { if let p = pendingPreset { cfg = ThemeEditing.applying(p, to: cfg) }; pendingPreset = nil }
            Button("Cancel", role: .cancel) { pendingPreset = nil }
        } message: { Text("Fonts, colours, text position, logo and background are replaced. The name stays.") }
        .alert("Couldn't save", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .task { await model.content.loadSupport() }
    }

    // MARK: Preview

    private var samplePicker: some View {
        Picker("Sample", selection: $sample) { ForEach(ThemeEditing.Sample.allCases) { Text($0.label).tag($0) } }
            .pickerStyle(.segmented)
    }

    private func previews(landscapeMax: CGFloat, portraitWidth: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(spacing: 4) {
                SlidePreview(frame: sample.frame, theme: resolved, background: background, shape: .landscape, live: true)
                    .frame(maxWidth: landscapeMax)
                if wide { Text("Landscape 16:9").font(.caption2).foregroundStyle(.secondary) }
            }
            VStack(spacing: 4) {
                SlidePreview(frame: sample.frame, theme: resolved, background: background, shape: .portrait, live: true)
                    .frame(width: portraitWidth)
                if wide { Text("Portrait 9:16").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: Form

    private var form: some View {
        Form {
            if readOnly { Section { Banner(text: "You have view-only access to themes.", style: .info) } }
            else if dirty, let p = problem { Section { Banner(text: p, style: .warning) } }

            Section {
                TextField("Theme name", text: $name).accessibilityLabel("Theme name")
                Menu {
                    ForEach(ThemePreset.all) { p in Button { pendingPreset = p } label: { Text("\(p.name): \(p.blurb)") } }
                } label: { Label("Create from preset", systemImage: "wand.and.stars") }
            } header: { Text("Name") } footer: { Text("Theme names must be unique in your church.") }

            Section("Text") {
                Picker("Font", selection: Binding(get: { cfg.font ?? .lato }, set: { cfg.font = $0 })) {
                    Text("Lato (clean)").tag(ThemeFont.lato)
                    Text("Julius (classic)").tag(ThemeFont.julius)
                }
                Picker("Align", selection: Binding(get: { cfg.align ?? .center }, set: { cfg.align = $0 })) {
                    Text("Centre").tag(SlideAlign.center)
                    Text("Left").tag(SlideAlign.left)
                }
                Picker("Where the text sits", selection: Binding(get: { cfg.position ?? .center }, set: { cfg.position = $0 })) {
                    Text("Middle").tag(TextPosition.center)
                    Text("Lower").tag(TextPosition.lower)
                    Text("Top").tag(TextPosition.top)
                }
            }

            Section {
                slider("Title size", value: Binding(get: { cfg.titleScale ?? 1 }, set: { cfg.titleScale = $0 }), range: 0.5...1.5, step: 0.05, percent: true)
                slider("Body size", value: Binding(get: { cfg.bodyScale ?? 1 }, set: { cfg.bodyScale = $0 }), range: 0.5...1.5, step: 0.05, percent: true)
                slider("Margin", value: Binding(get: { cfg.margin ?? 8 }, set: { cfg.margin = $0 }), range: 0...20, step: 1, percent: false)
            } header: { Text("Size") } footer: { Text("Song lyrics use the title size. Text shrinks to fit when a slide has a lot of words.") }

            Section {
                ColorRow(title: "Text colour", hex: Binding(get: { cfg.textColor ?? "#FFFFFF" }, set: { cfg.textColor = $0 }))
                if let w = ThemeEditing.contrastWarning(cfg) {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                        .accessibilityLabel("Warning. \(w)")
                } else if ThemeEditing.contrastRatio(cfg) == nil {
                    Text("The contrast check works for plain colours and gradients. With a picture or video, use the Dim slider so the words stay readable.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Colour") }

            Section("Effects") {
                Toggle("Shadow behind text", isOn: Binding(get: { cfg.shadow ?? true }, set: { cfg.shadow = $0 }))
                Toggle("Dark outline on text", isOn: Binding(get: { cfg.outline ?? false }, set: { cfg.outline = $0 }))
                Toggle("Show section labels on lyric slides", isOn: Binding(get: { cfg.showLabels ?? true }, set: { cfg.showLabels = $0 }))
            }

            Section {
                Toggle("Show the church logo", isOn: Binding(get: { cfg.logo?.show ?? false }, set: { setLogo(show: $0, position: nil) }))
                Picker("Corner", selection: Binding(get: { cfg.logo?.position ?? .bottomLeft }, set: { setLogo(show: nil, position: $0) })) {
                    Text("Bottom left").tag(LogoPosition.bottomLeft)
                    Text("Bottom right").tag(LogoPosition.bottomRight)
                    Text("Top left").tag(LogoPosition.topLeft)
                    Text("Top right").tag(LogoPosition.topRight)
                }
                .disabled(!(cfg.logo?.show ?? false))
            } header: { Text("Church logo") } footer: { Text("The logo is the one in your church settings on the website.") }

            Section {
                BackgroundLink(title: "Default background", value: $cfg.background, inheritLabel: "Use default (church colour)", readOnly: readOnly, previewTheme: cfg)
            } header: { Text("Background") } footer: { Text("A deck's background, or a slide's own, beats this one.") }

            if !wide {
                Section("Preview sample") { samplePicker }
            }
        }
        .disabled(readOnly)
        .scrollDismissesKeyboard(.interactively)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, percent: Bool) -> some View {
        let text = percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue.rounded()))%"
        return VStack(alignment: .leading) {
            Text("\(title): \(text)")
            Slider(value: value, in: range, step: step).accessibilityLabel(title).accessibilityValue(text)
        }
    }

    private func setLogo(show: Bool?, position: LogoPosition?) {
        cfg.logo = ThemeLogo(show: show ?? cfg.logo?.show ?? false, position: position ?? cfg.logo?.position ?? .bottomLeft, extra: cfg.logo?.extra ?? [:])
    }

    // MARK: Save

    private func save() {
        guard canSave else { return }
        var t = theme
        t.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        t.config = cfg
        saving = true
        Task {
            do {
                let saved = try await model.content.save(t)
                name = saved.name; originalName = saved.name
                originalCfg = cfg
                Haptics.success()
                saving = false
                dismiss()
            } catch {
                errorText = Formatting.message(for: error)
                Haptics.failure()
                saving = false
            }
        }
    }
}
