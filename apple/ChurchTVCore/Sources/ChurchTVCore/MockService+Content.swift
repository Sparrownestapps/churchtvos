import Foundation

// Demo-mode implementation of the content API: everything lives in memory (`store`) and resets when the demo restarts.

extension MockService {
    // MARK: Playlists

    /// Same refusal as the database trigger: with the NDI flag off, an NDI entry cannot be added or changed (removing is fine).
    private func checkNdi(old: [NdiSettings], new: [NdiSettings]) throws {
        if !Self.demoNdiEnabled, NdiRules.addsOrChanges(old: old, new: new) { throw ChurchError(NdiRules.notEnabledMessage) }
    }

    private func delay() async { try? await Task.sleep(nanoseconds: 120_000_000) }

    public func listPlaylists(kind: PlaylistKind, organizationId: UUID) async throws -> [Playlist] {
        await delay()
        return (kind == .kids ? store.kids : store.signage).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func createPlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist {
        await delay()
        let d = draft.cleaned()
        try checkNdi(old: [], new: d.items.ndiEntries)
        let row = Playlist(id: d.id, organizationId: Self.churchId, siteId: d.siteId, name: d.name, items: d.items, createdAt: Date(), updatedAt: Date())
        if kind == .kids { store.kids.append(row) } else { store.signage.append(row) }
        return row
    }

    public func updatePlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist {
        await delay()
        let d = draft.cleaned()
        func apply(_ list: inout [Playlist]) throws -> Playlist {
            guard let i = list.firstIndex(where: { $0.id == d.id }) else { throw ChurchError("Couldn't save \"\(d.name)\". It may have been deleted, or you may not have permission.") }
            try checkNdi(old: list[i].items.ndiEntries, new: d.items.ndiEntries)
            list[i].name = d.name; list[i].siteId = d.siteId; list[i].items = d.items; list[i].updatedAt = Date()
            return list[i]
        }
        return kind == .kids ? try apply(&store.kids) : try apply(&store.signage)
    }

    public func duplicatePlaylist(kind: PlaylistKind, playlist: Playlist) async throws -> Playlist {
        var copy = PlaylistDraft(playlist)
        copy.id = UUID(); copy.isNew = true; copy.name = ContentNaming.copyName(playlist.name)
        return try await createPlaylist(kind: kind, draft: copy)
    }

    public func deletePlaylist(kind: PlaylistKind, id: UUID, organizationId: UUID) async throws {
        await delay()
        // Same refusal as the database trigger for a playlist in a repeating schedule.
        if kind == .kids, id == Self.braveList.id {
            throw ChurchError("\"\(Self.braveList.name)\" is used by a repeating schedule (Sunday Kids rotation). Remove it there first.")
        }
        if kind == .kids { store.kids.removeAll { $0.id == id } } else { store.signage.removeAll { $0.id == id } }
    }

    // MARK: Decks

    public func listDecks(organizationId: UUID) async throws -> [SlideDeck] {
        await delay()
        return store.decks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func createDeck(draft: DeckDraft) async throws -> SlideDeck {
        await delay()
        let d = draft.cleaned()
        try checkNdi(old: [], new: d.slides.ndiEntries)
        let row = SlideDeck(id: d.id, organizationId: Self.churchId, siteId: d.siteId, name: d.name, themeId: d.themeId, background: d.background,
                            slides: d.slides, loops: d.loops, createdAt: Date(), updatedAt: Date())
        store.decks.append(row)
        return row
    }

    public func updateDeck(draft: DeckDraft) async throws -> SlideDeck {
        await delay()
        let d = draft.cleaned()
        guard let i = store.decks.firstIndex(where: { $0.id == d.id }) else {
            throw ChurchError("Couldn't save \"\(d.name)\". It may have been deleted, or you may not have permission.")
        }
        try checkNdi(old: store.decks[i].slides.ndiEntries, new: d.slides.ndiEntries)
        store.decks[i].name = d.name; store.decks[i].siteId = d.siteId; store.decks[i].themeId = d.themeId
        store.decks[i].background = d.background; store.decks[i].slides = d.slides; store.decks[i].loops = d.loops
        store.decks[i].updatedAt = Date()
        return store.decks[i]
    }

    public func duplicateDeck(deck: SlideDeck) async throws -> SlideDeck {
        var copy = DeckDraft(deck)
        copy.id = UUID(); copy.isNew = true; copy.name = ContentNaming.copyName(deck.name)
        return try await createDeck(draft: copy)
    }

    public func deleteDeck(id: UUID, organizationId: UUID) async throws {
        await delay()
        if id == Self.sundayDeck.id {
            throw ChurchError("\"\(Self.sundayDeck.name)\" is used by a repeating schedule (Sunday mornings). Remove it there first.")
        }
        store.decks.removeAll { $0.id == id }
    }

    // MARK: Themes

    public func listThemes(organizationId: UUID) async throws -> [SlideTheme] {
        await delay()
        return store.themes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func createTheme(organizationId: UUID, name: String, config: ThemeConfig) async throws -> SlideTheme {
        await delay()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.themes.contains(where: { $0.name.lowercased() == n.lowercased() }) {
            throw ChurchError("A theme with that name already exists. Choose another name.")
        }
        let row = SlideTheme(organizationId: Self.churchId, name: n, config: config, createdAt: Date(), updatedAt: Date())
        store.themes.append(row)
        return row
    }

    public func updateTheme(_ theme: SlideTheme) async throws -> SlideTheme {
        await delay()
        let n = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = store.themes.firstIndex(where: { $0.id == theme.id }) else {
            throw ChurchError("Couldn't save \"\(n)\". It may have been deleted, or you may not have permission.")
        }
        if store.themes.contains(where: { $0.id != theme.id && $0.name.lowercased() == n.lowercased() }) {
            throw ChurchError("A theme with that name already exists. Choose another name.")
        }
        store.themes[i].name = n; store.themes[i].config = theme.config; store.themes[i].updatedAt = Date()
        return store.themes[i]
    }

    public func duplicateTheme(_ theme: SlideTheme, existingNames: [String]) async throws -> SlideTheme {
        try await createTheme(organizationId: Self.churchId, name: ContentNaming.uniqueName(ContentNaming.copyName(theme.name), existing: existingNames), config: theme.config)
    }

    public func deleteTheme(id: UUID, organizationId: UUID) async throws {
        await delay()
        store.themes.removeAll { $0.id == id }
        // The database sets theme_id to null on decks that used it.
        for i in store.decks.indices where store.decks[i].themeId == id { store.decks[i].themeId = nil }
    }

    // MARK: Library

    public func listSongs(organizationId: UUID) async throws -> [Song] {
        store.songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func listMedia(organizationId: UUID, module: AppModule, kinds: Set<MediaKind>) async throws -> [MediaItem] {
        await delay()
        return store.media.filter { $0.module == module.rawValue && (kinds.isEmpty || kinds.contains($0.kind)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func uploadMediaItem(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> MediaItem? {
        for step in 1...10 {
            try await Task.sleep(nanoseconds: 120_000_000)
            progress(Double(step) / 10)
        }
        let palette = [("1d4ed8", "7c3aed"), ("2e7d5b", "f59e0b"), ("b3261e", "f59e0b"), ("0b3c5d", "328cc1")]
        let (a, b) = palette[store.media.count % palette.count]
        let item = MediaItem(organizationId: Self.churchId, module: request.module.rawValue, folderId: request.folderId, title: request.title, kind: request.kind,
                             storagePath: "demo/\(UUID().uuidString.lowercased())", url: DemoMedia.url(request.kind, a, b), sizeBytes: request.sizeBytes, createdAt: Date())
        store.media.append(item)
        return item
    }

    // MARK: Sites and locations

    public func listSites(organizationId: UUID) async throws -> [Site] { store.sites }
    public func listLocations(organizationId: UUID) async throws -> [Location] { store.locations }
}
