import SwiftUI
import ChurchTVCore

/// Where the Create section can push to. The editors are the placeholder views in EditorPlaceholders.swift (replaced by later agents).
public enum CreateRoute: Hashable {
    case playlist(PlaylistKind, PlaylistDraft)
    case deck(DeckDraft)
    case theme(SlideTheme)
}

/// The Create section: owns its navigation stack (a tab on iPhone, the detail of the "Create" sidebar entry on iPad).
public struct CreateRoot: View {
    @State private var path: [CreateRoute] = []
    private let initialSection: String?

    /// - Parameter initialSection: `kids`, `signage`, `slides` or `themes` pins the list to that one section (the Mac sidebar has one entry for each);
    ///   nil shows the segmented pickers.
    public init(initialSection: String? = nil) { self.initialSection = initialSection }

    public var body: some View {
        NavigationStack(path: $path) {
            CreateView(path: $path, pinnedSection: initialSection)
                .navigationDestination(for: CreateRoute.self) { route in
                    switch route {
                    case .playlist(let kind, let draft): PlaylistEditorView(kind: kind, playlist: draft)
                    case .deck(let draft): DeckEditorView(deck: draft)
                    case .theme(let theme): ThemeEditorView(theme: theme)
                    }
                }
        }
    }
}

/// Lists of Kids playlists, Signage playlists, Slides decks and Slides themes with create, duplicate, delete and schedule.
/// Only shown to owners, admins and editors (see `AppModel.canCreate`).
public struct CreateView: View {
    @Environment(ContentModel.self) private var model
    @Binding var path: [CreateRoute]
    private let pinnedSection: String?

    public init(path: Binding<[CreateRoute]>, pinnedSection: String? = nil) { _path = path; self.pinnedSection = pinnedSection }

    private enum SlidesTab: String, CaseIterable { case decks = "Decks", themes = "Themes" }

    @State private var section: CreateSection = .kids
    @State private var slidesTab: SlidesTab = .decks
    @State private var showName = false
    @State private var newName = ""
    @State private var pendingPreset: ThemePreset?
    @State private var errorText: String?
    @State private var toDelete: DeleteTarget?
    @State private var scheduleTarget: ScheduleTarget?
    @State private var started = false

    private struct DeleteTarget: Identifiable {
        enum Item { case playlist(Playlist, PlaylistKind), deck(SlideDeck), theme(SlideTheme) }
        let item: Item
        var id: UUID { switch item { case .playlist(let p, _): return p.id; case .deck(let d): return d.id; case .theme(let t): return t.id } }
        var name: String { switch item { case .playlist(let p, _): return p.name; case .deck(let d): return d.name; case .theme(let t): return t.name } }
    }

    private var content: ContentModel { model }
    private var sections: [CreateSection] { CreateSection.allCases.filter { model.church?.editableModules.contains($0.module) ?? false } }
    private var pinnedTitle: String {
        switch pinnedSection {
        case "kids": return "Kids playlists"
        case "signage": return "Signage playlists"
        case "slides": return "Slides decks"
        case "themes": return "Themes"
        default: return "Create"
        }
    }
    private var showingThemes: Bool { section == .slides && slidesTab == .themes }

    public var body: some View {
        List {
            if sections.count > 1 && pinnedSection == nil {
                Section {
                    Picker("Module", selection: $section) { ForEach(sections) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            if section == .slides && pinnedSection == nil {
                Section {
                    Picker("Show", selection: $slidesTab) { ForEach(SlidesTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            if let e = content.loadError { Section { Banner(text: e, style: .error) } }

            switch section {
            case .kids, .signage: playlistRows(section.playlistKind!)
            case .slides: if slidesTab == .decks { deckRows } else { themeRows }
            }
        }
        .macReadableWidth(820)
        .navigationTitle(pinnedTitle)
        .toolbar {
            ToolbarItem(placement: .trailingBar) { addMenu }
        }
        .refreshable { await content.load(section, force: true); await content.loadSupport(force: true) }
        .task {
            if !started { started = true; applyLaunchSection() }
            await content.loadSupport()
            await content.load(section)
        }
        .onChange(of: section) { _, s in Task { await content.load(s) } }
        .alert(newTitle, isPresented: $showName) {
            TextField("Name", text: $newName)
            Button("Create") { createNew() }
            Button("Cancel", role: .cancel) { pendingPreset = nil }
        } message: { Text(newMessage) }
        .alert("Couldn't finish", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .confirmationDialog(toDelete.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let t = toDelete { delete(t) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(deleteMessage) }
        .sheet(item: $scheduleTarget) { ScheduleSheet(target: $0) }
    }

    // MARK: Rows

    @ViewBuilder private func playlistRows(_ kind: PlaylistKind) -> some View {
        let list = content.playlists(kind)
        Section {
            ForEach(list) { p in
                NavigationLink(value: CreateRoute.playlist(kind, PlaylistDraft(p))) {
                    HStack(spacing: 12) {
                        if let first = p.items.first {
                            PlaylistItemPreview(item: first, songs: content.songLookup, defaultColor: SlideMetrics.defaultNavy).frame(width: 72)
                        } else { emptyThumb }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.headline).lineLimit(2)
                            Text(subtitle(count: p.itemCount, noun: "item", updated: p.updatedAt, site: p.siteId)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { toDelete = DeleteTarget(item: .playlist(p, kind)) } label: { Label("Delete", systemImage: "trash") }
                    Button { run { try await content.duplicate(p, kind: kind) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.blue)
                }
                .swipeActions(edge: .leading) {
                    Button { scheduleTarget = .playlist(id: p.id, name: p.name, kind: kind) } label: { Label("Schedule…", systemImage: "calendar.badge.plus") }.tint(.indigo)
                }
                .contextMenu {
                    Button { scheduleTarget = .playlist(id: p.id, name: p.name, kind: kind) } label: { Label("Schedule…", systemImage: "calendar.badge.plus") }
                    Button { run { try await content.duplicate(p, kind: kind) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { toDelete = DeleteTarget(item: .playlist(p, kind)) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } footer: { if !list.isEmpty { Text("Swipe a row to duplicate, schedule or delete.") } }
        if list.isEmpty { emptyState(loaded: content.loadedSections.contains(kind.rawValue), title: "No \(kind == .kids ? "Kids" : "Signage") playlists yet",
                                       text: kind == .kids ? "A Kids playlist is what a children's room plays: videos, countdowns, lyrics and more." : "A Signage playlist is the loop a lobby screen shows: images, videos, signs and live streams.") }
    }

    @ViewBuilder private var deckRows: some View {
        Section {
            ForEach(content.decks) { d in
                NavigationLink(value: CreateRoute.deck(DeckDraft(d))) {
                    HStack(spacing: 12) {
                        if let first = d.slides.first {
                            SlidePreview(slide: first, deckBackground: d.background, theme: content.theme(id: d.themeId)?.config, songs: content.songLookup)
                                .frame(width: 72)
                        } else { emptyThumb }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.name).font(.headline).lineLimit(2)
                            Text(subtitle(count: d.slideCount, noun: "slide", updated: d.updatedAt, site: d.siteId)).font(.caption).foregroundStyle(.secondary)
                            if let t = content.theme(id: d.themeId) { Label(t.name, systemImage: "paintpalette").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { toDelete = DeleteTarget(item: .deck(d)) } label: { Label("Delete", systemImage: "trash") }
                    Button { run { try await content.duplicate(d) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.blue)
                }
                .swipeActions(edge: .leading) {
                    Button { scheduleTarget = .deck(id: d.id, name: d.name) } label: { Label("Schedule…", systemImage: "calendar.badge.plus") }.tint(.indigo)
                }
                .contextMenu {
                    Button { scheduleTarget = .deck(id: d.id, name: d.name) } label: { Label("Schedule…", systemImage: "calendar.badge.plus") }
                    Button { run { try await content.duplicate(d) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { toDelete = DeleteTarget(item: .deck(d)) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } footer: { if !content.decks.isEmpty { Text("Swipe a row to duplicate, schedule or delete.") } }
        if content.decks.isEmpty { emptyState(loaded: content.loadedSections.contains("slides"), title: "No decks yet", text: "A deck is a presentation: text, songs, countdowns, images and video for your screens.") }
    }

    @ViewBuilder private var themeRows: some View {
        Section {
            ForEach(content.themes) { t in
                NavigationLink(value: CreateRoute.theme(t)) {
                    HStack(spacing: 12) {
                        SlidePreview(frame: .text(layout: .titleBody, title: "Welcome", body: "We're glad you're here.", align: nil, color: nil),
                                     theme: t.config.resolved, background: BackgroundResolver.resolve(slide: nil, deck: nil, theme: t.config.background))
                            .frame(width: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.name).font(.headline)
                            Text("\(decksUsing(t)) \(decksUsing(t) == 1 ? "deck" : "decks")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { toDelete = DeleteTarget(item: .theme(t)) } label: { Label("Delete", systemImage: "trash") }
                    Button { run { try await content.duplicate(t) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.blue)
                }
                .contextMenu {
                    Button { run { try await content.duplicate(t) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { toDelete = DeleteTarget(item: .theme(t)) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } footer: { Text("A theme is a reusable look for decks: font, colours, text position, background and logo.") }
        if content.themes.isEmpty { emptyState(loaded: content.loadedSections.contains("slides"), title: "No themes yet", text: "Create a theme, then choose it in a deck.") }
    }

    private var emptyThumb: some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.tertiaryFill).aspectRatio(16.0 / 9.0, contentMode: .fit).frame(width: 72)
            .overlay { Image(systemName: "rectangle.dashed").foregroundStyle(.secondary) }
    }

    @ViewBuilder private func emptyState(loaded: Bool, title: String, text: String) -> some View {
        if loaded {
            ContentUnavailableView { Label(title, systemImage: section.module.symbol) } description: { Text(text) } actions: {
                Button("Create one") { startNew() }.buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        } else if content.loadError == nil {
            HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        }
    }

    // MARK: Toolbar and new items

    @ViewBuilder private var addMenu: some View {
        if showingThemes {
            Menu {
                Button { pendingPreset = nil; startNew() } label: { Label("Blank theme", systemImage: "plus") }
                Section("From a preset") {
                    ForEach(ThemePreset.all) { p in Button(p.name) { pendingPreset = p; startNew() } }
                }
            } label: { Label("New theme", systemImage: "plus") }
        } else {
            Button { startNew() } label: { Label(newTitle, systemImage: "plus") }
        }
    }

    private var newTitle: String {
        if showingThemes { return "New theme" }
        switch section { case .kids: return "New Kids playlist"; case .signage: return "New Signage playlist"; case .slides: return "New deck" }
    }
    private var newMessage: String {
        if showingThemes { return "Give the theme a name. Names must be unique." }
        return "Give it a name. You can change it later."
    }

    private func startNew() {
        newName = showingThemes ? ContentNaming.uniqueName(pendingPreset?.name ?? "New theme", existing: content.themes.map(\.name)) : ""
        showName = true
    }

    private func createNew() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { pendingPreset = nil; return }
        Task {
            await content.loadSupport()
            switch section {
            case .kids, .signage:
                let kind = section.playlistKind!
                path.append(.playlist(kind, content.newPlaylistDraft(name: name)))
            case .slides:
                if slidesTab == .themes {
                    do {
                        let theme = try await content.createTheme(name: name, config: pendingPreset?.config ?? .standard)
                        path.append(.theme(theme))
                    } catch { errorText = Formatting.message(for: error); Haptics.failure() }
                    pendingPreset = nil
                } else {
                    path.append(.deck(content.newDeckDraft(name: name)))
                }
            }
        }
    }

    /// Test launch argument `-create kids|signage|slides|themes`; otherwise the first module the member can edit.
    private func applyLaunchSection() {
        let arg = pinnedSection ?? model.initialCreateSection
        if arg == "themes", sections.contains(.slides) { section = .slides; slidesTab = .themes }
        else if let a = arg.flatMap(CreateSection.init(rawValue:)), sections.contains(a) { section = a }
        else if !sections.contains(section), let first = sections.first { section = first }
        #if DEBUG
        // Test launch argument `-schedule deck|kids|signage` opens the Schedule sheet for a demo item.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-schedule"), i + 1 < args.count {
            switch args[i + 1] {
            case "deck": scheduleTarget = .deck(id: MockService.sundayDeck.id, name: MockService.sundayDeck.name)
            case "kids": scheduleTarget = .playlist(id: MockService.braveList.id, name: MockService.braveList.name, kind: .kids)
            case "signage": scheduleTarget = .playlist(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-000700000001")!, name: "Lobby loop", kind: .signage)
            default: break
            }
        }
        #endif
    }

    // MARK: Actions

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); Haptics.success() }
            catch { errorText = Formatting.message(for: error); Haptics.failure() }
        }
    }

    private func delete(_ t: DeleteTarget) {
        run {
            switch t.item {
            case .playlist(let p, let kind): try await content.delete(p, kind: kind)
            case .deck(let d): try await content.delete(d)
            case .theme(let th): try await content.delete(th)
            }
        }
    }

    private var deleteMessage: String {
        switch toDelete?.item {
        case .theme: return "Decks that use it fall back to the default look. Their slides are not changed."
        case .deck: return "This deck is deleted from every screen and schedule that uses it."
        default: return "This playlist is deleted from every screen and schedule that uses it."
        }
    }

    private func decksUsing(_ t: SlideTheme) -> Int { content.decks.filter { $0.themeId == t.id }.count }

    private func subtitle(count: Int, noun: String, updated: Date?, site: UUID?) -> String {
        var parts = ["\(count) \(noun)\(count == 1 ? "" : "s")"]
        if let updated { parts.append("Updated \(Formatting.ago(updated))") }
        if site != nil { parts.append(content.siteName(site)) }
        return parts.joined(separator: " · ")
    }
}
