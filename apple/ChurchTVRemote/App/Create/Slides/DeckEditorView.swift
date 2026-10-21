import SwiftUI
import ChurchTVCore

/// Edits a deck (DeckEditor.tsx): name, scope, theme, deck background, loop; a strip of live slide thumbnails; a large preview;
/// and the selected slide's form. Pushed by the Create list (`CreateRoute.deck`). Saves through `model.content.save(DeckDraft)`.
struct DeckEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var draft: DeckDraft
    @State private var original: DeckDraft
    @State private var selectedId: String?
    @State private var saving = false
    @State private var errorText: String?
    @State private var justSaved = false
    @State private var confirmDiscard = false
    @State private var deleteIndex: Int?
    @State private var showReorder = false
    @State private var showPlayNow = false
    @State private var previewShape: FrameShape = .landscape
    @State private var frameIndex = 0
    @State private var library: MediaLibrary?

    init(deck: DeckDraft) {
        _draft = State(initialValue: deck)
        _original = State(initialValue: deck)
        _selectedId = State(initialValue: deck.slides.first?.id)
    }

    // MARK: Derived

    private var content: ContentModel { model.content }
    private var theme: SlideTheme? { content.theme(id: draft.themeId) }
    private var dirty: Bool { draft != original }
    private var readOnly: Bool {
        guard let church = model.church else { return false }
        return !ContentPermissions.canEditContent(role: church.role, modules: church.modules, siteIds: church.siteIds, module: .slides, siteId: original.siteId)
    }
    private var canSave: Bool { !readOnly && !saving && DeckEditing.canSave(draft: draft, original: original) }
    private var selectedIndex: Int? { draft.slides.firstIndex { $0.id == selectedId } }
    private var selected: DeckSlide? { selectedIndex.map { draft.slides[$0] } }
    private var songs: SongLookup { content.songLookup }
    private var wide: Bool { sizeClass == .regular }
    private var showScope: Bool { content.hasAllSites || content.selectableSites.count > 1 }

    private func label(_ s: DeckSlide) -> String { DeckEditing.label(s, songs: songs) { content.mediaTitle(forId: $0) } }

    // MARK: Body

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    mainList
                    Divider()
                    ScrollView { previewPanel.padding() }
                        .frame(width: 440)
                        .background(Color(.secondarySystemGroupedBackground))
                }
            } else {
                mainList
            }
        }
        .navigationTitle(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "New deck" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(dirty ? "Cancel" : "Close") { if dirty { confirmDiscard = true } else { dismiss() } }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                if canPlayNow { Button { showPlayNow = true } label: { Label("Play now", systemImage: "play.fill") } }
                if !readOnly { Button(saving ? "Saving…" : "Save") { save() }.disabled(!canSave) }
            }
        }
        .confirmationDialog("You have unsaved changes.", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Leave without saving this deck?") }
        .confirmationDialog(deleteIndex.map { i in "Delete slide \(i + 1) (\(draft.slides.indices.contains(i) ? label(draft.slides[i]) : ""))?" } ?? "",
                            isPresented: Binding(get: { deleteIndex != nil }, set: { if !$0 { deleteIndex = nil } }), titleVisibility: .visible) {
            Button("Delete slide", role: .destructive) { if let i = deleteIndex { delete(i) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .sheet(isPresented: $showReorder) { ReorderSlidesSheet(slides: $draft.slides) { label($0) } theme: { theme?.config } deckBackground: { draft.background } songs: { songs } }
        .sheet(isPresented: $showPlayNow) { DeckPlayNowSheet(deckId: draft.id, name: draft.name) }
        .task {
            await content.loadSupport()
            library = try? await content.mediaLibrary(.slides)
        }
        .onChange(of: selectedId) { _, _ in frameIndex = 0 }
        .onChange(of: draft.slides.map(\.id)) { _, ids in
            if let s = selectedId, !ids.contains(s) { selectedId = ids.first }
        }
    }

    // MARK: Main list

    private var mainList: some View {
        List {
            if readOnly { Section { Banner(text: "You have view-only access to this deck.", style: .info) } }
            else if dirty, let p = draft.problem { Section { Banner(text: p, style: .warning) } }
            if justSaved && !dirty && !readOnly {
                Section { Label("Saved. The TVs use the new version from now on.", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline) }
            }
            settingsSection
            stripSection
            if !wide { Section("Preview") { previewPanel.listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)) } }
            if let s = selected, let id = selectedId {
                Section {
                    HStack { Label("\(kindName(s)) slide \((selectedIndex ?? 0) + 1) of \(draft.slides.count)", systemImage: s.kind?.symbol ?? "questionmark.square.dashed").font(.headline); Spacer() }
                        .accessibilityAddTraits(.isHeader)
                }
                SlideFormSections(slide: slideBinding(id), deckBackground: draft.background, theme: theme?.config, readOnly: readOnly)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func kindName(_ s: DeckSlide) -> String { s.kind?.name ?? "Unknown" }

    // MARK: Settings

    @ViewBuilder private var settingsSection: some View {
        Section {
            TextField("Deck name, for example Sunday welcome loop", text: $draft.name)
                .accessibilityLabel("Deck name")
                .disabled(readOnly)
            Picker("Theme", selection: $draft.themeId) {
                Text("No theme (default look)").tag(UUID?.none)
                ForEach(content.themes) { t in Text(t.name).tag(UUID?.some(t.id)) }
                if let id = draft.themeId, content.theme(id: id) == nil { Text("Theme removed").tag(UUID?.some(id)) }
            }
            .disabled(readOnly)
            if showScope {
                Picker("Available to", selection: $draft.siteId) {
                    if content.hasAllSites { Text("All sites").tag(UUID?.none) }
                    ForEach(content.selectableSites) { s in Text(s.name).tag(UUID?.some(s.id)) }
                    if let id = draft.siteId, !content.selectableSites.contains(where: { $0.id == id }) { Text(content.siteName(id)).tag(UUID?.some(id)) }
                }
                .disabled(readOnly)
            }
            Toggle("Loop at the end", isOn: $draft.loops).disabled(readOnly)
            BackgroundLink(title: "Deck background", value: $draft.background, inheritLabel: "Use theme background", readOnly: readOnly,
                           previewTheme: theme?.config)
        } header: { Text("Deck") } footer: {
            Text(draft.loops ? "When the last slide ends the deck starts again from slide 1. A slide's own background beats the deck's, and the deck's beats the theme's."
                             : "Without looping, the TV returns to its home screen after the last slide. A slide's own background beats the deck's, and the deck's beats the theme's.")
        }
    }

    // MARK: Strip

    @ViewBuilder private var stripSection: some View {
        Section {
            HStack {
                if !readOnly { addMenu }
                Spacer()
                if draft.slides.count > 1 && !readOnly {
                    Button { showReorder = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                        .buttonStyle(.bordered)
                }
            }
            .listRowSeparator(.hidden)
            if draft.slides.isEmpty {
                Text("No slides yet.\(readOnly ? "" : " Use Add slide to start.")").foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(Array(draft.slides.enumerated()), id: \.element.id) { i, s in thumb(s, i) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .onChange(of: selectedId) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityLabel("Slides")
                if !readOnly, let i = selectedIndex { toolsRow(i) }
            }
        } header: { Text("Slides (\(draft.slides.count))") } footer: {
            if !draft.slides.isEmpty && !readOnly { Text("Touch and hold a thumbnail to drag it, or use Reorder or the arrows.") }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(DeckSlide.Kind.allCases, id: \.self) { k in
                Button { add(k) } label: { Label("\(k.name): \(Self.hint(k))", systemImage: k.symbol) }
            }
        } label: { Label("Add slide", systemImage: "plus") }
        .buttonStyle(.borderedProminent)
    }

    static func hint(_ k: DeckSlide.Kind) -> String {
        switch k {
        case .text: return "title and words"
        case .media: return "a picture or video"
        case .song: return "lyrics from the library"
        case .countdown: return "a timer"
        case .stream: return "a live HLS feed"
        case .blank: return "a plain colour"
        }
    }

    private func thumb(_ s: DeckSlide, _ i: Int) -> some View {
        let on = s.id == selectedId
        let isUnknown = s.kind == nil
        return Button { selectedId = s.id; Haptics.selection() } label: {
            VStack(spacing: 4) {
                SlidePreview(slide: s, deckBackground: draft.background, theme: theme?.config, songs: songs)
                    .frame(width: 132)
                    .overlay(alignment: .topLeading) {
                        Text("\(i + 1)").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule()).padding(4)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isUnknown { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.white).padding(5).background(.black.opacity(0.6), in: Circle()).padding(4) }
                    }
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: on ? 3 : 0).padding(-3) }
                Text(label(s)).font(.caption2).lineLimit(1).frame(width: 132)
                    .foregroundStyle(on ? Color.accentColor : .secondary)
            }
            .padding(4)
        }
        .buttonStyle(.plain)
        .id(s.id)
        .draggable(s.id) { SlidePreview(slide: s, deckBackground: draft.background, theme: theme?.config, songs: songs).frame(width: 120) }
        .dropDestination(for: String.self) { items, _ in
            guard !readOnly, let from = items.first else { return false }
            DeckEditing.move(id: from, onto: s.id, in: &draft.slides)
            return true
        }
        .contextMenu {
            if !readOnly {
                Button { DeckEditing.move(i, by: -1, in: &draft.slides) } label: { Label("Move earlier", systemImage: "arrow.left") }.disabled(i == 0)
                Button { DeckEditing.move(i, by: 1, in: &draft.slides) } label: { Label("Move later", systemImage: "arrow.right") }.disabled(i == draft.slides.count - 1)
                Button { duplicate(i) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { deleteIndex = i } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide \(i + 1), \(kindName(s)), \(label(s))")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Move earlier") { if !readOnly { DeckEditing.move(i, by: -1, in: &draft.slides) } }
        .accessibilityAction(named: "Move later") { if !readOnly { DeckEditing.move(i, by: 1, in: &draft.slides) } }
        .accessibilityAction(named: "Duplicate") { if !readOnly { duplicate(i) } }
        .accessibilityAction(named: "Delete") { if !readOnly { deleteIndex = i } }
    }

    private func toolsRow(_ i: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            Button { DeckEditing.move(i, by: -1, in: &draft.slides) } label: { Label("Earlier", systemImage: "arrow.left").frame(maxWidth: .infinity) }
                .disabled(i == 0).accessibilityLabel("Move slide \(i + 1) earlier")
            Button { DeckEditing.move(i, by: 1, in: &draft.slides) } label: { Label("Later", systemImage: "arrow.right").frame(maxWidth: .infinity) }
                .disabled(i == draft.slides.count - 1).accessibilityLabel("Move slide \(i + 1) later")
            Button { duplicate(i) } label: { Label("Duplicate", systemImage: "plus.square.on.square").frame(maxWidth: .infinity) }
            Button(role: .destructive) { deleteIndex = i } label: { Label("Delete", systemImage: "trash").frame(maxWidth: .infinity) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .listRowBackground(Color.clear)
    }

    // MARK: Preview

    @ViewBuilder private var previewPanel: some View {
        VStack(spacing: 10) {
            if let s = selected {
                let count = SlideRender.frames(for: s, songs: songs).count
                let i = min(frameIndex, max(0, count - 1))
                Picker("Shape", selection: $previewShape) {
                    Text("Landscape 16:9").tag(FrameShape.landscape)
                    Text("Portrait 9:16").tag(FrameShape.portrait)
                }
                .pickerStyle(.segmented)
                SlidePreview(slide: s, frameIndex: i, deckBackground: draft.background, theme: theme?.config, songs: songs, shape: previewShape, live: true)
                    .frame(maxWidth: previewShape == .landscape ? 560 : 230)
                if count > 1 {
                    HStack {
                        Button { frameIndex = max(0, i - 1) } label: { Label("Back", systemImage: "chevron.left") }.disabled(i == 0)
                        Spacer()
                        Text("Screen \(i + 1) of \(count)").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button { frameIndex = min(count - 1, i + 1) } label: { Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon) }.disabled(i == count - 1)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Text("Add a slide to see a preview.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func slideBinding(_ id: String) -> Binding<DeckSlide> {
        Binding(get: { draft.slides.first { $0.id == id } ?? DeckSlide(id: id, content: .blank(BlankSlideContent())) },
                set: { new in if let i = draft.slides.firstIndex(where: { $0.id == id }) { draft.slides[i] = new } })
    }

    private func add(_ kind: DeckSlide.Kind) {
        selectedId = DeckEditing.add(kind, to: &draft.slides, after: selectedId)
        justSaved = false
        Haptics.selection()
    }

    private func duplicate(_ i: Int) {
        if let id = DeckEditing.duplicate(i, in: &draft.slides) { selectedId = id; Haptics.selection() }
    }

    private func delete(_ i: Int) {
        selectedId = DeckEditing.remove(i, from: &draft.slides)
        deleteIndex = nil
    }

    private var canPlayNow: Bool { !draft.isNew && !dirty && !readOnly && model.canControl }

    private func save() {
        guard canSave else { return }
        saving = true
        let toSave = draft.cleaned()
        Task {
            do {
                let saved = try await content.save(toSave)
                let d = DeckDraft(saved)
                draft = d; original = d
                justSaved = true
                Haptics.success()
                await model.loadPlayNow()
            } catch {
                errorText = Formatting.message(for: error)
                Haptics.failure()
            }
            saving = false
        }
    }
}

// MARK: - Reorder

/// "Reorder" mode: a list of the slides with move handles (drag the grip, or use VoiceOver's Move actions).
struct ReorderSlidesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var slides: [DeckSlide]
    var label: (DeckSlide) -> String
    var theme: () -> ThemeConfig?
    var deckBackground: () -> SlideBackground?
    var songs: () -> SongLookup

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(slides.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                        SlidePreview(slide: s, deckBackground: deckBackground(), theme: theme(), songs: songs()).frame(width: 96)
                        Text(label(s)).lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Slide \(i + 1), \(label(s))")
                }
                .onMove { slides.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder slides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Play now

/// Starts the saved deck on a TV (the Remote's Play now command with kind 'deck').
struct DeckPlayNowSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deckId: UUID
    let name: String
    @State private var screenId: UUID?
    @State private var minutes = 60
    @State private var sending = false
    private let durations = [15, 30, 60, 90, 120, 240, 480]

    var body: some View {
        NavigationStack {
            Form {
                Section("TV") {
                    if model.screens.isEmpty {
                        Text("No TVs found for this church.").foregroundStyle(.secondary)
                    } else {
                        Picker("Play on", selection: $screenId) {
                            ForEach(model.screens) { s in Text(s.screen.displayName).tag(UUID?.some(s.id)) }
                        }
                        .pickerStyle(.inline).labelsHidden()
                    }
                }
                Section {
                    Picker("Play for", selection: $minutes) { ForEach(durations, id: \.self) { Text(Formatting.minutes($0)).tag($0) } }
                } footer: { Text("After that the TV returns to its schedule.") }
                if let e = model.commandError { Section { Banner(text: e, style: .error) } }
            }
            .navigationTitle("Play “\(name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Start") { start() }.disabled(screenId == nil || sending) }
            }
            .onAppear {
                model.commandError = nil
                if screenId == nil { screenId = model.selectedScreenId ?? model.screens.first?.id }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func start() {
        guard let screen = model.screens.first(where: { $0.id == screenId }) else { return }
        sending = true
        Task {
            let ok = await model.send(.start(kind: .deck, id: deckId, minutes: minutes), to: screen)
            sending = false
            if ok { dismiss() }
        }
    }
}
