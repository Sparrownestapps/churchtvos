import Foundation

/// Content editing API: Kids playlists, Signage playlists, decks, themes, songs, media and locations.
/// `SupabaseService` implements it against the real tables; `MockService` in memory (demo mode). Every method has a default
/// implementation that throws "not available", so other conformers (the Mac app only uses `SupabaseService`) keep compiling.
///
/// Conventions:
///  - Every insert sets `organization_id`. Row-level security decides who may write; refusals come back as readable `ChurchError`s.
///  - Server messages pass through unchanged, for example `"Sunday" is used by a repeating schedule (...). Remove it there first.`
///    or `"Song" is used in: .... Remove it from those playlists first.` Show `error.localizedDescription` to the user.
///  - New rows are created from a draft whose `id` was made on the device; the returned row is the saved version.
public protocol ContentService: Sendable {
    // Kids and Signage playlists
    func listPlaylists(kind: PlaylistKind, organizationId: UUID) async throws -> [Playlist]
    func createPlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist
    func updatePlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist
    /// Copies a playlist as "<name> (copy)".
    func duplicatePlaylist(kind: PlaylistKind, playlist: Playlist) async throws -> Playlist
    func deletePlaylist(kind: PlaylistKind, id: UUID, organizationId: UUID) async throws

    // Slides decks
    func listDecks(organizationId: UUID) async throws -> [SlideDeck]
    func createDeck(draft: DeckDraft) async throws -> SlideDeck
    func updateDeck(draft: DeckDraft) async throws -> SlideDeck
    func duplicateDeck(deck: SlideDeck) async throws -> SlideDeck
    func deleteDeck(id: UUID, organizationId: UUID) async throws

    // Themes (names are unique per church)
    func listThemes(organizationId: UUID) async throws -> [SlideTheme]
    func createTheme(organizationId: UUID, name: String, config: ThemeConfig) async throws -> SlideTheme
    func updateTheme(_ theme: SlideTheme) async throws -> SlideTheme
    func duplicateTheme(_ theme: SlideTheme, existingNames: [String]) async throws -> SlideTheme
    func deleteTheme(id: UUID, organizationId: UUID) async throws

    // Library
    /// Every song with sections and arrangement (all pages).
    func listSongs(organizationId: UUID) async throws -> [Song]
    /// Files of one library (module), optionally only some kinds. Pages through the table, so more than 1000 files work.
    func listMedia(organizationId: UUID, module: AppModule, kinds: Set<MediaKind>) async throws -> [MediaItem]
    /// Same as `ChurchService.uploadMedia` but returns the new library row so a picker can select it (nil if the server did not say).
    func uploadMediaItem(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> MediaItem?

    // Sites and locations
    func listSites(organizationId: UUID) async throws -> [Site]
    /// Locations with their module tags (`Location.modules`) and site.
    func listLocations(organizationId: UUID) async throws -> [Location]
}

public extension ContentService {
    private var unavailable: ChurchError { ChurchError("Editing content is not available here.") }

    func listPlaylists(kind: PlaylistKind, organizationId: UUID) async throws -> [Playlist] { throw unavailable }
    func createPlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist { throw unavailable }
    func updatePlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist { throw unavailable }
    func duplicatePlaylist(kind: PlaylistKind, playlist: Playlist) async throws -> Playlist { throw unavailable }
    func deletePlaylist(kind: PlaylistKind, id: UUID, organizationId: UUID) async throws { throw unavailable }
    func listDecks(organizationId: UUID) async throws -> [SlideDeck] { throw unavailable }
    func createDeck(draft: DeckDraft) async throws -> SlideDeck { throw unavailable }
    func updateDeck(draft: DeckDraft) async throws -> SlideDeck { throw unavailable }
    func duplicateDeck(deck: SlideDeck) async throws -> SlideDeck { throw unavailable }
    func deleteDeck(id: UUID, organizationId: UUID) async throws { throw unavailable }
    func listThemes(organizationId: UUID) async throws -> [SlideTheme] { throw unavailable }
    func createTheme(organizationId: UUID, name: String, config: ThemeConfig) async throws -> SlideTheme { throw unavailable }
    func updateTheme(_ theme: SlideTheme) async throws -> SlideTheme { throw unavailable }
    func duplicateTheme(_ theme: SlideTheme, existingNames: [String]) async throws -> SlideTheme { throw unavailable }
    func deleteTheme(id: UUID, organizationId: UUID) async throws { throw unavailable }
    func listSongs(organizationId: UUID) async throws -> [Song] { throw unavailable }
    func listMedia(organizationId: UUID, module: AppModule, kinds: Set<MediaKind>) async throws -> [MediaItem] { throw unavailable }
    func uploadMediaItem(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> MediaItem? { throw unavailable }
    func listSites(organizationId: UUID) async throws -> [Site] { throw unavailable }
    func listLocations(organizationId: UUID) async throws -> [Location] { throw unavailable }
}

/// Helpers shared by the services.
public enum ContentNaming {
    /// "<name> (copy)"; the website's theme duplicate adds " 2", " 3"... when a name is taken (names must be unique).
    public static func copyName(_ name: String) -> String { "\(name) (copy)" }

    /// `base` if free, otherwise `base 2`, `base 3`... (case-insensitive), like `nameFree` in ThemesPage.tsx.
    public static func uniqueName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}

/// Turns raw back-end messages into text for people. Messages the server wrote on purpose
/// (`raise exception` in delete protections, for example "is used in: ...") already read well and pass through unchanged.
public enum ContentErrors {
    public static func friendly(_ message: String, themeName: String? = nil) -> String {
        let m = message.lowercased()
        if m.contains("slide_themes_organization_id_name_key") || (m.contains("duplicate key") && m.contains("slide_themes")) {
            return "A theme with that name already exists. Choose another name."
        }
        if m.contains("duplicate key") && m.contains("media_folders") { return "A folder with that name already exists here." }
        if m.contains("row-level security") || m.contains("permission denied") {
            return "You do not have permission to change this. Ask a church admin."
        }
        if m.contains("jwt expired") { return "Your session expired. Sign in again." }
        return message
    }
}
