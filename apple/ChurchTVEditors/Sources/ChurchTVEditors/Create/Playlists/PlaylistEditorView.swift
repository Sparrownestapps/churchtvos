import SwiftUI
import ChurchTVCore

/// Edits a Kids or Signage playlist. Pushed by the Create list (`CreateRoute.playlist`).
/// `playlist` is the working copy: a new draft (`isNew`) is inserted on first save, an existing one is updated.
///
/// Header (name, who it is available to), the list of items (tap to edit, drag to reorder with "Reorder", swipe to duplicate or delete,
/// "Add item" menu with exactly the item types of the kind), Save, Cancel with an unsaved-changes confirmation and, for Kids playlists,
/// "Play now" once the playlist is saved. Mirrors dashboard/src/pages/PlaylistsPage.tsx and SignagePlaylistsPage.tsx.
public struct PlaylistEditorView: View {
    @Environment(ContentModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: PlaylistKind
    let playlist: PlaylistDraft

    @State private var draft: PlaylistDraft
    @State private var original: PlaylistDraft
    @State private var branding: OrgBranding?
    @State private var editingItem: UUID?
    @State private var editMode: EditMode = .inactive
    @State private var saving = false
    @State private var errorText: String?
    @State private var justSaved = false
    @State private var confirmDiscard = false
    @State private var showPlayNow = false

    public init(kind: PlaylistKind, playlist: PlaylistDraft) {
        self.kind = kind
        self.playlist = playlist
        _draft = State(initialValue: playlist)
        _original = State(initialValue: playlist)
    }

    private var content: ContentModel { model }
    private var dirty: Bool { PlaylistEditing.hasChanges(draft: draft, original: original) }
    private var canSave: Bool { PlaylistEditing.canSave(draft: draft, original: original, kind: kind) && !saving }
    private var problem: String? { draft.problem(kind: kind) }
    private var defaultColor: String { branding?.primaryColor ?? SlideMetrics.defaultNavy }
    /// The item types in the Add menu. EXPERIMENTAL: NDI is offered in Kids playlists only when the church has the flag.
    private var addableTypes: [PlaylistItem.TypeName] { kind.itemTypes + (kind == .kids && model.ndiEnabled ? [.ndi] : []) }
    private var canPlayNow: Bool { kind == .kids && !draft.isNew && !dirty && model.canPlayNow }

    public var body: some View {
        List {
            headerSection
            if justSaved && !dirty { savedSection }
            else if canPlayNow { playNowSection }
            itemsSection
            addSection
            Section {
            } footer: {
                Text(kind == .kids
                     ? "Tip: for screens turned to portrait, use portrait media (1080 x 1920). YouTube items don't rotate on portrait screens."
                     : "Tip: for screens turned to portrait, use portrait media (1080 x 1920). Signs preview both shapes.")
            }
        }
        .environment(\.editMode, $editMode)
        .macReadableWidth()
        .navigationTitle(draft.name.isEmpty ? "New playlist" : draft.name)
        .inlineNavigationTitle()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(dirty ? "Cancel" : "Close") { if dirty { confirmDiscard = true } else { dismiss() } }
                    .cancelShortcut()
                    .accessibilityHint(dirty ? "Asks before discarding your changes" : "Closes the editor")
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else { Button("Save") { Task { await save() } }.bold().disabled(!canSave).saveShortcut() }
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("What you changed in this playlist has not been saved.") }
        .alert("Couldn't save", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .navigationDestination(item: $editingItem) { uid in
            PlaylistItemEditorView(kind: kind, item: itemBinding(uid), branding: branding, defaultColor: defaultColor)
        }
        .sheet(isPresented: $showPlayNow) { model.playNowView(.playlist(id: draft.id, name: draft.name)) }
        .task {
            await content.loadSupport()
            await loadBranding()
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            TextField(kind == .kids ? "e.g. Elementary · Week 3" : "e.g. Lobby · Weekday loop", text: $draft.name)
                .autocapitalizeWords()
                .accessibilityLabel("Playlist name")
            sitePicker
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("Playlist name") } footer: {
            if kind == .signage { Text("Signage playlists are shown on lobby screens by scheduling them. They can't be started with Play now.") }
        }
    }

    @ViewBuilder private var sitePicker: some View {
        let sites = content.selectableSites
        let showAll = content.hasAllSites
        let known = draft.siteId == nil ? showAll : sites.contains { $0.id == draft.siteId }
        if sites.count + (showAll ? 1 : 0) > 1 || !known {
            Picker("Available to", selection: $draft.siteId) {
                if showAll { Text("All sites").tag(UUID?.none) }
                ForEach(sites) { Text($0.name).tag(Optional($0.id)) }
                if !known { Text(content.siteName(draft.siteId)).tag(draft.siteId) }
            }
        } else {
            LabeledContent("Available to", value: content.siteName(draft.siteId))
        }
    }

    private var savedSection: some View {
        Section {
            Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            if kind == .kids, model.canPlayNow {
                Button { showPlayNow = true } label: { Label("Play now on a TV…", systemImage: "play.rectangle.fill") }
            }
        }
    }

    private var playNowSection: some View {
        Section {
            Button { showPlayNow = true } label: { Label("Play now on a TV…", systemImage: "play.rectangle.fill") }
        }
    }

    private var itemsSection: some View {
        Section {
            if draft.items.isEmpty {
                Text("No items yet. Use Add item below.").foregroundStyle(.secondary)
            }
            ForEach(Array(draft.items.enumerated()), id: \.element.uid) { index, item in
                row(item, index: index)
            }
            .onMove { from, to in draft.items = PlaylistEditing.moved(draft.items, from: from, to: to) }
            .onDelete { offsets in draft.items.remove(atOffsets: offsets) }
        } header: {
            HStack {
                Text("Items")
                Spacer()
                #if os(iOS)   // on the Mac rows are dragged directly
                if draft.items.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") { withAnimation { editMode = editMode.isEditing ? .inactive : .active } }
                        .font(.subheadline.weight(.medium)).textCase(nil)
                        .accessibilityHint("Shows handles to drag items into a new order")
                }
                #endif
            }
        } footer: {
            if !draft.items.isEmpty { Text(PlaylistEditing.summary(draft.items)) }
        }
    }

    private func row(_ item: PlaylistItem, index: Int) -> some View {
        let text = PlaylistEditing.rowText(item, songs: content.songLookup, kind: kind)
        let invalid = item.problem != nil
        return Button { editingItem = item.uid } label: {
            HStack(spacing: 12) {
                PlaylistItemPreview(item: item, songs: content.songLookup, defaultColor: defaultColor)
                    .frame(width: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title).font(.body).foregroundStyle(.primary).lineLimit(1)
                    Text("\(index + 1). \(item.typeName == .ndi && !model.ndiEnabled ? "NDI · switched off" : text.detail)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if invalid { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Needs attention") }
                if !editMode.isEditing {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Item \(index + 1) of \(draft.items.count): \(text.title). \(text.detail)\(invalid ? ". Needs attention" : "")")
        .accessibilityHint("Opens the item editor")
        .accessibilityAction(named: "Move up") { move(index, by: -1) }
        .accessibilityAction(named: "Move down") { move(index, by: 1) }
        .accessibilityAction(named: "Duplicate") { PlaylistEditing.duplicate(at: index, in: &draft.items, allowNdi: model.ndiEnabled) }
        .accessibilityAction(named: "Delete") { draft.items.remove(at: index) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { draft.items.remove(at: index) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { withAnimation { PlaylistEditing.duplicate(at: index, in: &draft.items, allowNdi: model.ndiEnabled) }; Haptics.selection() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                .tint(.indigo)
                .disabled(item.typeName == .ndi && !model.ndiEnabled)
        }
    }

    private var addSection: some View {
        Section {
            Menu {
                ForEach(addableTypes, id: \.self) { type in
                    Button { add(type) } label: { Label(PlaylistEditorLabels.menuLabel(type, kind: kind), systemImage: type.symbol) }
                }
            } label: {
                Label("Add item", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("Choose what to add: " + addableTypes.map { PlaylistEditorLabels.menuLabel($0, kind: kind) }.joined(separator: ", "))
            ImportButton(playlistItems: $draft.items, kind: kind, siteId: draft.siteId)
        }
    }

    // MARK: Actions

    private func add(_ type: PlaylistItem.TypeName) {
        let item = PlaylistEditing.newItem(type, kind: kind, churchName: model.church?.organization.name ?? "", branding: branding)
        withAnimation { draft.items.append(item) }
        Haptics.selection()
        // Media, links and signs need something chosen right away, so open the new item.
        if type != .countdown { editingItem = item.uid }
    }

    private func move(_ index: Int, by delta: Int) {
        let to = index + delta
        guard draft.items.indices.contains(to) else { return }
        withAnimation { draft.items.swapAt(index, to) }
    }

    private func itemBinding(_ uid: UUID) -> Binding<PlaylistItem> {
        Binding(
            get: { draft.items.first { $0.uid == uid } ?? PlaylistItem(.unknown(UnknownItem(raw: [:])), uid: uid) },
            set: { new in if let i = draft.items.firstIndex(where: { $0.uid == uid }) { draft.items[i] = new } }
        )
    }

    private func save() async {
        guard canSave else { return }
        saving = true
        defer { saving = false }
        do {
            let saved = try await content.save(draft.cleaned(), kind: kind)
            let fresh = PlaylistDraft(saved)
            draft = fresh; original = fresh
            justSaved = true
            Haptics.success()
            await model.loadPlayNow()
        } catch {
            errorText = Formatting.message(for: error)
            Haptics.failure()
        }
    }

    private func loadBranding() async {
        if model.isDemo { branding = .demo; return }
        guard let org = model.church?.id, let service = model.service as? SupabaseService else { return }
        branding = try? await service.organizationBranding(organizationId: org)
    }
}

enum PlaylistEditorLabels {
    /// Menu and heading text per item type (the website says "Slide" for Kids pictures; the TV outline says "Picture").
    static func menuLabel(_ type: PlaylistItem.TypeName, kind: PlaylistKind) -> String {
        switch type {
        case .image: return kind == .kids ? "Picture" : "Image"
        case .sign: return "Sign"
        case .stream: return "Live stream"
        case .youtube: return "YouTube"
        case .ndi: return NdiText.label
        default: return type.label
        }
    }
}
