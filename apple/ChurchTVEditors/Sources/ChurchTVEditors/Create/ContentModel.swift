import Foundation
import Observation
import SwiftUI
import ChurchTVCore

/// Which list the Create section shows.
public enum CreateSection: String, Hashable, CaseIterable, Identifiable {
    case kids, signage, slides
    public var id: String { rawValue }
    public var module: AppModule { AppModule(rawValue: rawValue)! }
    public var title: String { module.displayName }
    public var playlistKind: PlaylistKind? { self == .kids ? .kids : self == .signage ? .signage : nil }
}

/// Content state and actions for the Create section and for every editor. Owned by the app (the Remote's `AppModel.content`); it reaches the session through a `ContentHost`.
///
/// Editors never talk to the service directly for saving: they call `save(...)`, which inserts or updates, keeps the lists in sync and
/// throws a `ChurchError` whose text is safe to show in an alert (server refusals pass through unchanged).
@MainActor
@Observable
public final class ContentModel {
    @ObservationIgnored unowned let host: ContentHost
    public init(host: ContentHost) { self.host = host }

    // Lists (Create section)
    private(set) var kids: [Playlist] = []
    private(set) var signage: [Playlist] = []
    private(set) var decks: [SlideDeck] = []
    private(set) var themes: [SlideTheme] = []
    private(set) var loadedSections: Set<String> = []
    private(set) var isLoading = false
    /// Last load error (shown as a banner in the list).
    var loadError: String?

    // Shared support data (previews, pickers, new drafts)
    private(set) var songs: [Song] = []
    private(set) var sites: [Site] = []
    private(set) var locations: [Location] = []
    private(set) var supportLoaded = false

    // Media libraries per module (kept until an upload or a pull to refresh)
    private var libraries: [AppModule: MediaLibrary] = [:]
    private var mediaTitles: [String: String] = [:]

    var service: any ChurchService { host.service }
    var organizationId: UUID? { host.church?.id }
    public var church: ChurchAccess? { host.church }
    /// The church's TVs (empty on a host that has none, such as the Mac editors). Used for schedule time zones and Play now.
    var screens: [ScreenInfo] { host.screens }
    var isDemo: Bool { host.service.isDemo }
    /// Adding media needs the Editor role or above and a live module.
    public var canAddMedia: Bool { (church?.role.canEditContent ?? false) && !(church?.modules.isEmpty ?? true) }
    /// Play now buttons appear only when the host can start things on a TV and there is a TV.
    var canPlayNow: Bool { host.supportsPlayNow && !screens.isEmpty }
    func loadPlayNow() async { await host.loadPlayNow() }
    var canControl: Bool { host.supportsPlayNow && (church?.role.canControl ?? false) }
    var initialCreateSection: String? { host.initialCreateSection }
    func playNowView(_ target: PlayNowTarget) -> AnyView { host.playNowView(target) ?? AnyView(EmptyView()) }

    /// Forget everything loaded (call on sign out or when the church changes).
    public func reset() {
        kids = []; signage = []; decks = []; themes = []; songs = []; sites = []; locations = []
        loadedSections = []; supportLoaded = false; libraries = [:]; mediaTitles = [:]; loadError = nil
    }

    // MARK: Derived

    /// Songs by id text, for previews and outlines.
    var songLookup: SongLookup { Song.lookup(songs) }
    func playlists(_ kind: PlaylistKind) -> [Playlist] { kind == .kids ? kids : signage }
    func theme(id: UUID?) -> SlideTheme? { id.flatMap { id in themes.first { $0.id == id } } }
    func siteName(_ id: UUID?) -> String { id.flatMap { id in sites.first { $0.id == id }?.name } ?? "All sites" }
    /// The sites this member may pick for new content ("All sites" is offered only when `church.hasAllSites`).
    var selectableSites: [Site] { church?.selectableSites(from: sites) ?? [] }
    var defaultSiteId: UUID? { church?.defaultSiteId(from: sites) }
    var hasAllSites: Bool { church?.hasAllSites ?? true }
    func mediaTitle(forId id: String) -> String? { mediaTitles[id.lowercased()] }

    // MARK: Loading

    func load(_ section: CreateSection, force: Bool = false) async {
        guard let org = organizationId else { return }
        if !force && loadedSections.contains(section.rawValue) { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch section {
            case .kids: kids = try await service.listPlaylists(kind: .kids, organizationId: org)
            case .signage: signage = try await service.listPlaylists(kind: .signage, organizationId: org)
            case .slides:
                async let d = service.listDecks(organizationId: org)
                async let t = service.listThemes(organizationId: org)
                (decks, themes) = try await (d, t)
            }
            loadedSections.insert(section.rawValue)
            loadError = nil
        } catch {
            if !(error is CancellationError) { loadError = Formatting.message(for: error) }
        }
    }

    /// Songs, sites, locations and themes: what previews and the editors' pickers need. Cheap to call again.
    func loadSupport(force: Bool = false) async {
        guard let org = organizationId else { return }
        if supportLoaded && !force { return }
        async let s = try? service.listSongs(organizationId: org)
        async let si = try? service.listSites(organizationId: org)
        async let l = try? service.listLocations(organizationId: org)
        async let t = try? service.listThemes(organizationId: org)
        let (songs, sites, locations, themes) = await (s, si, l, t)
        self.songs = songs ?? self.songs
        self.sites = sites ?? self.sites
        self.locations = locations ?? self.locations
        if let themes { self.themes = themes }
        supportLoaded = true
    }

    /// The library (files and folders) of one module. `force` re-reads it (after an upload).
    func mediaLibrary(_ module: AppModule, force: Bool = false) async throws -> MediaLibrary {
        if !force, let cached = libraries[module] { return cached }
        guard let org = organizationId else { return MediaLibrary(module: module) }
        async let items = service.listMedia(organizationId: org, module: module, kinds: [])
        async let folders = service.mediaFolders(organizationId: org, module: module)
        let lib = MediaLibrary(module: module, items: try await items, folders: try await folders)
        libraries[module] = lib
        for m in lib.items { mediaTitles[m.id.uuidString.lowercased()] = m.title }
        return lib
    }

    /// Folders of a module's library (empty on error). For the Add media screen.
    func folders(for module: AppModule) async -> [MediaFolder] {
        guard let org = organizationId else { return [] }
        return (try? await service.mediaFolders(organizationId: org, module: module)) ?? []
    }

    func invalidateMedia(_ module: AppModule) { libraries[module] = nil }

    // MARK: New drafts

    func newPlaylistDraft(name: String) -> PlaylistDraft {
        PlaylistDraft(organizationId: organizationId ?? UUID(), siteId: defaultSiteId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func newDeckDraft(name: String) -> DeckDraft {
        DeckDraft(organizationId: organizationId ?? UUID(), siteId: defaultSiteId, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                  themeId: nil, slides: [])
    }

    // MARK: Saving (used by the editors)

    /// Inserts a new playlist or updates an existing one, and keeps the list in sync. Throws a readable `ChurchError`.
    @discardableResult
    func save(_ draft: PlaylistDraft, kind: PlaylistKind) async throws -> Playlist {
        if let problem = draft.problem(kind: kind) { throw ChurchError(problem) }
        let saved = draft.isNew ? try await service.createPlaylist(kind: kind, draft: draft) : try await service.updatePlaylist(kind: kind, draft: draft)
        upsert(saved, kind: kind)
        return saved
    }

    @discardableResult
    func save(_ draft: DeckDraft) async throws -> SlideDeck {
        if let problem = draft.problem { throw ChurchError(problem) }
        let saved = draft.isNew ? try await service.createDeck(draft: draft) : try await service.updateDeck(draft: draft)
        if let i = decks.firstIndex(where: { $0.id == saved.id }) { decks[i] = saved } else { decks.append(saved) }
        decks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return saved
    }

    @discardableResult
    func save(_ theme: SlideTheme) async throws -> SlideTheme {
        let saved = try await service.updateTheme(theme)
        if let i = themes.firstIndex(where: { $0.id == saved.id }) { themes[i] = saved }
        themes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return saved
    }

    private func upsert(_ p: Playlist, kind: PlaylistKind) {
        var list = playlists(kind)
        if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.append(p) }
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if kind == .kids { kids = list } else { signage = list }
    }

    // MARK: List actions

    func duplicate(_ p: Playlist, kind: PlaylistKind) async throws {
        upsert(try await service.duplicatePlaylist(kind: kind, playlist: p), kind: kind)
    }

    func delete(_ p: Playlist, kind: PlaylistKind) async throws {
        guard let org = organizationId else { return }
        try await service.deletePlaylist(kind: kind, id: p.id, organizationId: org)
        if kind == .kids { kids.removeAll { $0.id == p.id } } else { signage.removeAll { $0.id == p.id } }
        await host.loadPlayNow()
    }

    func duplicate(_ d: SlideDeck) async throws {
        let copy = try await service.duplicateDeck(deck: d)
        decks.append(copy)
        decks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func delete(_ d: SlideDeck) async throws {
        guard let org = organizationId else { return }
        try await service.deleteDeck(id: d.id, organizationId: org)
        decks.removeAll { $0.id == d.id }
        await host.loadPlayNow()
    }

    func createTheme(name: String, config: ThemeConfig) async throws -> SlideTheme {
        guard let org = organizationId else { throw ChurchError("No church selected.") }
        let t = try await service.createTheme(organizationId: org, name: name, config: config)
        themes.append(t)
        themes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return t
    }

    func duplicate(_ t: SlideTheme) async throws {
        let copy = try await service.duplicateTheme(t, existingNames: themes.map(\.name))
        themes.append(copy)
        themes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func delete(_ t: SlideTheme) async throws {
        guard let org = organizationId else { return }
        try await service.deleteTheme(id: t.id, organizationId: org)
        themes.removeAll { $0.id == t.id }
        for i in decks.indices where decks[i].themeId == t.id { decks[i].themeId = nil }
    }

    /// Uploads a picked file and returns the new library row (nil if the server did not return it). Invalidates the module's cache.
    func uploadMedia(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> MediaItem? {
        defer { invalidateMedia(request.module) }
        return try await service.uploadMediaItem(request, progress: progress)
    }
}
