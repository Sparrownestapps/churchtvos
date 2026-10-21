import Foundation
import Supabase

// Content editing against the real tables (playlists, signage_playlists, decks, slide_themes, songs, media, sites, locations).
// Row-level security decides who may write; this code only maps errors. JSON columns are written through the content models, which keep
// every key they do not understand.

extension SupabaseService {
    static let mediaColumns = "id,organization_id,site_id,module,folder_id,title,kind,storage_path,url,size_bytes,created_at"
    static let playlistColumns = "id,organization_id,site_id,name,items,created_at,updated_at"
    static let deckColumns = "id,organization_id,site_id,name,theme_id,background,slides,loops,created_at,updated_at"
    static let themeColumns = "id,organization_id,name,config,created_at,updated_at"
    static let songColumns = "id,organization_id,title,authors,ccli_number,copyright,sections,arrangement,lines_per_slide,source,created_at,updated_at"

    private func contentRows<T: Decodable>(_ builder: PostgrestBuilder, as type: T.Type = T.self) async throws -> [T] {
        let response = try await builder.execute()
        do { return try ContentJSON.decoder().decode([T].self, from: response.data) }
        catch { throw ChurchError("The server sent something unexpected (\(type)). Update the app and try again.") }
    }

    /// Runs `work`, then replaces back-end jargon with readable text (server delete refusals pass through unchanged).
    private func content<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await guarded(work) }
        catch let e as ChurchError { throw ChurchError(ContentErrors.friendly(e.message)) }
    }

    /// Reads every page (1000 rows each) of a query.
    private func pagedRows<T: Decodable>(_ query: (Int, Int) -> PostgrestBuilder) async throws -> [T] {
        var all: [T] = []
        var from = 0
        while true {
            let page: [T] = try await contentRows(query(from, from + 999))
            all += page
            if page.count < 1000 { return all }
            from += 1000
        }
    }

    private func id(_ u: UUID) -> String { u.uuidString.lowercased() }

    // MARK: Playlists

    public func listPlaylists(kind: PlaylistKind, organizationId: UUID) async throws -> [Playlist] {
        try await content {
            try await pagedRows { a, b in
                client.from(kind.table).select(Self.playlistColumns).eq("organization_id", value: id(organizationId)).order("name").order("id").range(from: a, to: b)
            }
        }
    }

    public func createPlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist {
        try await content {
            let rows: [Playlist] = try await contentRows(client.from(kind.table).insert(draft.write(includeId: true)).select(Self.playlistColumns))
            guard let row = rows.first else { throw ChurchError("The playlist was not saved. You may not have permission.") }
            return row
        }
    }

    public func updatePlaylist(kind: PlaylistKind, draft: PlaylistDraft) async throws -> Playlist {
        try await content {
            let rows: [Playlist] = try await contentRows(
                client.from(kind.table).update(draft.write(includeId: false)).eq("id", value: id(draft.id)).eq("organization_id", value: id(draft.organizationId)).select(Self.playlistColumns))
            guard let row = rows.first else { throw ChurchError("Couldn't save \"\(draft.name)\". It may have been deleted, or you may not have permission.") }
            return row
        }
    }

    public func duplicatePlaylist(kind: PlaylistKind, playlist: Playlist) async throws -> Playlist {
        var copy = PlaylistDraft(playlist)
        copy.id = UUID(); copy.isNew = true; copy.name = ContentNaming.copyName(playlist.name)
        return try await createPlaylist(kind: kind, draft: copy)
    }

    public func deletePlaylist(kind: PlaylistKind, id uuid: UUID, organizationId: UUID) async throws {
        try await content {
            let rows: [IdRow] = try await contentRows(client.from(kind.table).delete().eq("id", value: id(uuid)).eq("organization_id", value: id(organizationId)).select("id"))
            if rows.isEmpty { throw ChurchError("Couldn't delete the playlist. You may not have permission.") }
        }
    }

    // MARK: Decks

    public func listDecks(organizationId: UUID) async throws -> [SlideDeck] {
        try await content {
            try await pagedRows { a, b in
                client.from("decks").select(Self.deckColumns).eq("organization_id", value: id(organizationId)).order("name").order("id").range(from: a, to: b)
            }
        }
    }

    public func createDeck(draft: DeckDraft) async throws -> SlideDeck {
        try await content {
            let rows: [SlideDeck] = try await contentRows(client.from("decks").insert(draft.write(includeId: true)).select(Self.deckColumns))
            guard let row = rows.first else { throw ChurchError("The deck was not saved. You may not have permission.") }
            return row
        }
    }

    public func updateDeck(draft: DeckDraft) async throws -> SlideDeck {
        try await content {
            let rows: [SlideDeck] = try await contentRows(
                client.from("decks").update(draft.write(includeId: false)).eq("id", value: id(draft.id)).eq("organization_id", value: id(draft.organizationId)).select(Self.deckColumns))
            guard let row = rows.first else { throw ChurchError("Couldn't save \"\(draft.name)\". It may have been deleted, or you may not have permission.") }
            return row
        }
    }

    public func duplicateDeck(deck: SlideDeck) async throws -> SlideDeck {
        var copy = DeckDraft(deck)
        copy.id = UUID(); copy.isNew = true; copy.name = ContentNaming.copyName(deck.name)
        return try await createDeck(draft: copy)
    }

    public func deleteDeck(id uuid: UUID, organizationId: UUID) async throws {
        try await content {
            let rows: [IdRow] = try await contentRows(client.from("decks").delete().eq("id", value: id(uuid)).eq("organization_id", value: id(organizationId)).select("id"))
            if rows.isEmpty { throw ChurchError("Couldn't delete the deck. You may not have permission.") }
        }
    }

    // MARK: Themes

    public func listThemes(organizationId: UUID) async throws -> [SlideTheme] {
        try await content {
            try await contentRows(client.from("slide_themes").select(Self.themeColumns).eq("organization_id", value: id(organizationId)).order("name"))
        }
    }

    public func createTheme(organizationId: UUID, name: String, config: ThemeConfig) async throws -> SlideTheme {
        try await content {
            let body = ThemeWrite(id: nil, organizationId: organizationId, name: name.trimmingCharacters(in: .whitespacesAndNewlines), config: config)
            let rows: [SlideTheme] = try await contentRows(client.from("slide_themes").insert(body).select(Self.themeColumns))
            guard let row = rows.first else { throw ChurchError("The theme was not saved. You may not have permission.") }
            return row
        }
    }

    public func updateTheme(_ theme: SlideTheme) async throws -> SlideTheme {
        try await content {
            let body = ThemeWrite(id: nil, organizationId: theme.organizationId, name: theme.name.trimmingCharacters(in: .whitespacesAndNewlines), config: theme.config)
            let rows: [SlideTheme] = try await contentRows(
                client.from("slide_themes").update(body).eq("id", value: id(theme.id)).eq("organization_id", value: id(theme.organizationId)).select(Self.themeColumns))
            guard let row = rows.first else { throw ChurchError("Couldn't save \"\(theme.name)\". It may have been deleted, or you may not have permission.") }
            return row
        }
    }

    public func duplicateTheme(_ theme: SlideTheme, existingNames: [String]) async throws -> SlideTheme {
        try await createTheme(organizationId: theme.organizationId, name: ContentNaming.uniqueName(ContentNaming.copyName(theme.name), existing: existingNames), config: theme.config)
    }

    public func deleteTheme(id uuid: UUID, organizationId: UUID) async throws {
        try await content {
            let rows: [IdRow] = try await contentRows(client.from("slide_themes").delete().eq("id", value: id(uuid)).eq("organization_id", value: id(organizationId)).select("id"))
            if rows.isEmpty { throw ChurchError("Couldn't delete the theme. You may not have permission.") }
        }
    }

    // MARK: Library

    public func listSongs(organizationId: UUID) async throws -> [Song] {
        try await content {
            try await pagedRows { a, b in
                client.from("songs").select(Self.songColumns).eq("organization_id", value: id(organizationId)).order("title").order("id").range(from: a, to: b)
            }
        }
    }

    public func listMedia(organizationId: UUID, module: AppModule, kinds: Set<MediaKind>) async throws -> [MediaItem] {
        try await content {
            try await pagedRows { a, b in
                var q = client.from("media").select(Self.mediaColumns).eq("organization_id", value: id(organizationId)).eq("module", value: module.rawValue)
                if !kinds.isEmpty { q = q.in("kind", values: kinds.map(\.rawValue).sorted()) }
                return q.order("title").order("id").range(from: a, to: b)
            }
        }
    }

    // MARK: Sites and locations

    public func listSites(organizationId: UUID) async throws -> [Site] {
        try await guarded { try await rows(client.from("sites").select("id,name,timezone").eq("organization_id", value: id(organizationId)).order("name")) }
    }

    public func listLocations(organizationId: UUID) async throws -> [Location] {
        try await guarded { try await rows(client.from("locations").select("id,name,site_id,modules").eq("organization_id", value: id(organizationId)).order("name")) }
    }

    private struct IdRow: Decodable { let id: UUID }
}
