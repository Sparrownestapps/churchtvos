import Foundation
import Supabase

// The real back end for the Mac app's operations, library and admin console. Same tables and functions the website calls
// (dashboard/src/pages/*.tsx, dashboard/src/admin/*.tsx). Row-level security decides who may write; this code maps errors.

extension SupabaseService {
    private func lower(_ u: UUID) -> String { u.uuidString.lowercased() }

    /// Decodes rows whose models spell their snake_case keys out (so no key strategy).
    private func plainRows<T: Decodable>(_ builder: PostgrestBuilder, as type: T.Type = T.self) async throws -> [T] {
        let response = try await builder.execute()
        do { return try ContentJSON.decoder().decode([T].self, from: response.data) }
        catch { throw ChurchError("The server sent something unexpected (\(type)). Update the app and try again.") }
    }

    /// `guarded` plus friendly texts for common database refusals.
    private func friendly<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await guarded(work) }
        catch let e as ChurchError { throw ChurchError(ContentErrors.friendly(e.message)) }
    }
}

// MARK: - Operations

extension SupabaseService: OperationsService {
    private struct ScreenRow: Decodable {
        let id: UUID; let name: String?; let locationId: UUID?; let orientation: String?; let defaultModule: String?
        let groupId: UUID?; let signageDefaultPlaylistId: UUID?; let autoplay: Bool?
        enum CodingKeys: String, CodingKey {
            case id, name, orientation, autoplay
            case locationId = "location_id", defaultModule = "default_module", groupId = "group_id", signageDefaultPlaylistId = "signage_default_playlist_id"
        }
    }

    public func isPlatformAdmin() async throws -> Bool {
        try await guarded {
            let response = try await client.rpc("is_platform_admin").execute()
            return (try? JSONDecoder().decode(Bool.self, from: response.data)) ?? false
        }
    }

    public func listModules(availableOnly: Bool) async throws -> [ModuleDef] {
        try await friendly {
            let base = client.from("modules").select("id,name,sort,available")
            return try await plainRows(availableOnly ? base.eq("available", value: true).order("sort") : base.order("sort"))
        }
    }

    // Screens

    public func loadScreenSettings(organizationId: UUID) async throws -> [UUID: ScreenSettings] {
        try await friendly {
            let list: [ScreenRow] = try await plainRows(
                client.from("screens").select("id,name,location_id,orientation,default_module,group_id,signage_default_playlist_id,autoplay")
                    .eq("organization_id", value: lower(organizationId)))
            return Dictionary(uniqueKeysWithValues: list.map { r in
                (r.id, ScreenSettings(screenId: r.id, name: r.name, locationId: r.locationId, orientation: r.orientation.flatMap(ScreenOrientation.init(rawValue:)) ?? .landscape,
                                      defaultModule: r.defaultModule ?? "kids", groupId: r.groupId, signageDefaultPlaylistId: r.signageDefaultPlaylistId, autoplay: r.autoplay ?? false))
            })
        }
    }

    public func updateScreen(_ settings: ScreenSettings) async throws {
        try await friendly {
            _ = try await client.from("screens").update(settings.updatePayload).eq("id", value: lower(settings.screenId)).execute()
        }
    }

    private struct ClaimParams: Encodable {
        let pCode: String; let pLocationId: String; let pName: String?
        enum CodingKeys: String, CodingKey { case pCode = "p_code", pLocationId = "p_location_id", pName = "p_name" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pCode, forKey: .pCode); try c.encode(pLocationId, forKey: .pLocationId); try c.encode(pName, forKey: .pName)
        }
    }

    public func claimScreen(code: String, locationId: UUID, name: String?) async throws {
        try await guarded {
            _ = try await client.rpc("claim_screen", params: ClaimParams(pCode: PairingCode.normalize(code), pLocationId: lower(locationId),
                                                                           pName: name?.trimmingCharacters(in: .whitespacesAndNewlines).blankToNil)).execute()
        }
    }

    public func releaseScreen(id: UUID) async throws {
        try await guarded { _ = try await client.rpc("release_screen", params: ["p_screen_id": lower(id)]).execute() }
    }

    public func tvLimit(organizationId: UUID) async throws -> Int? {
        try await guarded {
            let response = try await client.rpc("tv_limit", params: ["p_org": lower(organizationId)]).execute()
            return try? JSONDecoder().decode(Int.self, from: response.data)
        }
    }

    // People

    public func listMembers(organizationId: UUID) async throws -> [Member] {
        try await friendly {
            try await plainRows(client.from("memberships").select("id,organization_id,user_id,email,role,modules,site_ids,created_at")
                .eq("organization_id", value: lower(organizationId)).order("email"))
        }
    }

    public func inviteMember(organizationId: UUID, draft: AccessDraft) async throws {
        if let p = PeopleRules.problem(draft, isInvite: true) { throw ChurchError(p) }
        try await friendly { _ = try await client.from("memberships").insert(PeopleRules.insertRow(organizationId: organizationId, draft: draft)).execute() }
    }

    public func updateMember(id: UUID, draft: AccessDraft) async throws {
        if let p = PeopleRules.problem(draft, isInvite: false) { throw ChurchError(p) }
        try await friendly { _ = try await client.from("memberships").update(MembershipUpdatePayload(draft)).eq("id", value: lower(id)).execute() }
    }

    public func removeMember(id: UUID, organizationId: UUID) async throws {
        try await friendly {
            _ = try await client.from("memberships").delete().eq("id", value: lower(id)).eq("organization_id", value: lower(organizationId)).execute()
        }
    }

    // Church settings

    private struct OrgRow: Decodable { let id: UUID; let name: String; let slug: String; let branding: RawJSON? }

    public func loadOrganization(id: UUID) async throws -> OrganizationSettings {
        try await friendly {
            let rows: [OrgRow] = try await plainRows(client.from("organizations").select("id,name,slug,branding").eq("id", value: lower(id)).limit(1))
            guard let r = rows.first else { throw ChurchError("Could not load this church.") }
            return OrganizationSettings(id: r.id, name: r.name, slug: r.slug, branding: BrandingSettings(json: r.branding))
        }
    }

    private struct OrgUpdate: Encodable { let name: String; let branding: RawJSON }

    public func saveOrganization(id: UUID, name: String, branding: BrandingSettings) async throws {
        if let p = BrandingSettings.problem(name: name, youtubeChannelId: branding.youtubeChannelId ?? "") { throw ChurchError(p) }
        try await friendly {
            _ = try await client.from("organizations").update(OrgUpdate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), branding: branding.json))
                .eq("id", value: lower(id)).execute()
        }
    }

    public func uploadBrandingLogo(organizationId: UUID, fileURL: URL, contentType: String) async throws -> String {
        try await guarded {
            let path = BrandingSettings.logoPath(organizationId: organizationId, filename: fileURL.lastPathComponent)
            let bucket = client.storage.from(Config.mediaBucket)
            _ = try await bucket.upload(path, fileURL: fileURL, options: FileOptions(cacheControl: "3600", contentType: contentType, upsert: false))
            return try bucket.getPublicURL(path: path).absoluteString
        }
    }

    public func loadPlan(organizationId: UUID) async throws -> [PlanRow] {
        try await friendly {
            try await plainRows(client.from("entitlements").select("module,status,tv_limit,plan,current_period_end,grace_ends_at").eq("organization_id", value: lower(organizationId)))
        }
    }
}

// MARK: - Library

extension SupabaseService: LibraryService {
    private struct UsageRow: Decodable {
        let mediaId: UUID?; let songId: UUID?; let playlistNames: [String]?
        enum CodingKeys: String, CodingKey { case mediaId = "media_id", songId = "song_id", playlistNames = "playlist_names" }
    }

    public func mediaUsage(organizationId: UUID, module: AppModule) async throws -> [UUID: [String]] {
        try await friendly {
            let response = try await client.rpc("media_usage", params: ["p_org": lower(organizationId), "p_module": module.rawValue]).execute()
            let rows = (try? ContentJSON.decoder().decode([UsageRow].self, from: response.data)) ?? []
            return Dictionary(rows.compactMap { r in r.mediaId.map { ($0, r.playlistNames ?? []) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    private struct TitleUpdate: Encodable { let title: String }
    private struct FolderMove: Encodable {
        let folderId: UUID?
        enum CodingKeys: String, CodingKey { case folderId = "folder_id" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(folderId?.uuidString.lowercased(), forKey: .folderId)
        }
    }
    private struct ParentMove: Encodable {
        let parentId: UUID?
        enum CodingKeys: String, CodingKey { case parentId = "parent_id" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(parentId?.uuidString.lowercased(), forKey: .parentId)
        }
    }
    private struct NameUpdate: Encodable { let name: String }

    public func renameMedia(id: UUID, organizationId: UUID, title: String) async throws {
        try await friendly {
            _ = try await client.from("media").update(TitleUpdate(title: title.trimmingCharacters(in: .whitespacesAndNewlines)))
                .eq("id", value: lower(id)).eq("organization_id", value: lower(organizationId)).execute()
        }
    }

    public func deleteMedia(_ item: MediaItem, organizationId: UUID) async throws {
        try await friendly {
            // The row goes first: the database refuses a file a playlist still uses ("... is used in: ... Remove it from those playlists first.").
            let response = try await client.from("media").delete().eq("id", value: lower(item.id)).eq("organization_id", value: lower(organizationId)).select("id").execute()
            let gone = (try? JSONDecoder().decode([RawJSON].self, from: response.data)) ?? []
            if gone.isEmpty { throw ChurchError("Could not delete \"\(item.title)\". You may not have permission.") }
            // A leftover file is harmless; a missing one would break playlists.
            if let path = item.storagePath, !path.hasPrefix("demo/") { _ = try? await client.storage.from(Config.mediaBucket).remove(paths: [path]) }
        }
    }

    public func moveMedia(ids: [UUID], organizationId: UUID, module: AppModule, to folder: UUID?) async throws {
        guard !ids.isEmpty else { return }
        try await friendly {
            _ = try await client.from("media").update(FolderMove(folderId: folder)).in("id", values: ids.map(lower))
                .eq("organization_id", value: lower(organizationId)).eq("module", value: module.rawValue).execute()
        }
    }

    private struct NewFolderRow: Encodable {
        let organizationId: UUID; let module: String; let parentId: UUID?; let siteId: UUID?; let name: String
        enum CodingKeys: String, CodingKey { case module, name, organizationId = "organization_id", parentId = "parent_id", siteId = "site_id" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(organizationId.uuidString.lowercased(), forKey: .organizationId)
            try c.encode(module, forKey: .module)
            try c.encode(parentId?.uuidString.lowercased(), forKey: .parentId)
            try c.encode(siteId?.uuidString.lowercased(), forKey: .siteId)
            try c.encode(name, forKey: .name)
        }
    }

    public func createFolder(organizationId: UUID, module: AppModule, parent: UUID?, siteId: UUID?, name: String) async throws -> MediaFolder {
        try await friendly {
            let row = NewFolderRow(organizationId: organizationId, module: module.rawValue, parentId: parent, siteId: siteId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            let response = try await client.from("media_folders").insert(row).select("id,module,parent_id,name,site_id").execute()
            let list = (try? ChurchJSON.decoder().decode([MediaFolder].self, from: response.data)) ?? []
            guard let folder = list.first else { throw ChurchError("The folder was created but the server did not return it. Refresh the library.") }
            return folder
        }
    }

    public func renameFolder(id: UUID, organizationId: UUID, name: String) async throws {
        try await friendly {
            _ = try await client.from("media_folders").update(NameUpdate(name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
                .eq("id", value: lower(id)).eq("organization_id", value: lower(organizationId)).execute()
        }
    }

    public func moveFolder(id: UUID, organizationId: UUID, to parent: UUID?) async throws {
        try await friendly {
            _ = try await client.from("media_folders").update(ParentMove(parentId: parent)).eq("id", value: lower(id)).eq("organization_id", value: lower(organizationId)).execute()
        }
    }

    public func deleteFolder(id: UUID, organizationId: UUID) async throws {
        try await friendly {
            _ = try await client.from("media_folders").delete().eq("id", value: lower(id)).eq("organization_id", value: lower(organizationId)).execute()
        }
    }

    // Songs

    public func songUsage(organizationId: UUID) async throws -> [UUID: [String]] {
        try await friendly {
            let response = try await client.rpc("song_usage", params: ["p_org": lower(organizationId)]).execute()
            let rows = (try? ContentJSON.decoder().decode([UsageRow].self, from: response.data)) ?? []
            return Dictionary(rows.compactMap { r in r.songId.map { ($0, r.playlistNames ?? []) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    public func saveSong(_ draft: SongDraft, organizationId: UUID) async throws -> Song {
        if let p = draft.problem { throw ChurchError(p) }
        return try await friendly {
            let row = draft.row(organizationId: organizationId)
            let response: PostgrestResponse<Void>
            if let id = draft.id {
                response = try await client.from("songs").update(row).eq("id", value: lower(id)).select(SupabaseService.songColumns).execute()
            } else {
                response = try await client.from("songs").insert(row).select(SupabaseService.songColumns).execute()
            }
            guard let song = (try? ContentJSON.decoder().decode([Song].self, from: response.data))?.first else {
                throw ChurchError("Could not save \"\(draft.title)\". It may have been deleted, or you may not have permission.")
            }
            return song
        }
    }

    public func insertSongs(_ drafts: [SongDraft], organizationId: UUID) async throws {
        guard !drafts.isEmpty else { return }
        try await friendly { _ = try await client.from("songs").insert(drafts.map { $0.row(organizationId: organizationId) }).execute() }
    }

    public func deleteSong(id: UUID, organizationId: UUID) async throws {
        try await friendly { _ = try await client.from("songs").delete().eq("id", value: lower(id)).eq("organization_id", value: lower(organizationId)).execute() }
    }
}

// MARK: - Admin console

extension SupabaseService: AdminService {
    public func adminListOrganizations() async throws -> [AdminOrg] {
        try await guarded {
            let response = try await client.rpc("admin_list_organizations").execute()
            do { return try ChurchJSON.decoder().decode([AdminOrg].self, from: response.data) }
            catch { throw ChurchError("The server sent something unexpected (churches). Update the app and try again.") }
        }
    }

    public func adminUpdateOrganization(_ id: UUID, change: AdminOrgChange) async throws {
        try await guarded { _ = try await client.rpc("admin_update_organization", params: AdminUpdateParams(org: id, change: change)).execute() }
    }

    public func adminUpsertEntitlements(_ rows: [AdminEntitlementRow]) async throws {
        guard !rows.isEmpty else { return }
        try await guarded { _ = try await client.from("entitlements").upsert(rows.map(AdminLogic.cleanedEntitlement), onConflict: "organization_id,module").execute() }
    }

    public func adminDeleteEntitlement(organizationId: UUID, module: String) async throws {
        try await guarded {
            _ = try await client.from("entitlements").delete().eq("organization_id", value: organizationId.uuidString.lowercased()).eq("module", value: module).execute()
        }
    }

    private struct AuditRow: Decodable {
        let id: Int; let at: Date; let actorEmail: String?; let organizationId: UUID?; let action: String; let detail: RawJSON?
        enum CodingKeys: String, CodingKey { case id, at, action, detail, actorEmail = "actor_email", organizationId = "organization_id" }
    }

    public func adminListAudit(organizationId: UUID?, action: String?, page: Int, pageSize: Int) async throws -> [AuditEntry] {
        try await guarded {
            var q = client.from("admin_audit_log").select("id,at,actor_email,organization_id,action,detail")
            if let organizationId { q = q.eq("organization_id", value: organizationId.uuidString.lowercased()) }
            if let action { q = q.eq("action", value: action) }
            // One extra row tells the caller there is a next page.
            let rows: [AuditRow] = try await plainRows(q.order("at", ascending: false).order("id", ascending: false).range(from: page * pageSize, to: page * pageSize + pageSize))
            return rows.map { AuditEntry(id: $0.id, at: $0.at, actorEmail: $0.actorEmail, organizationId: $0.organizationId, action: $0.action, detail: $0.detail) }
        }
    }

    public func adminListMembers(organizationId: UUID) async throws -> [Member] { try await listMembers(organizationId: organizationId) }

    public func adminInviteMember(organizationId: UUID, email: String, role: Role, moduleIds: [String]) async throws {
        try await inviteMember(organizationId: organizationId, draft: AccessDraft(email: email, role: role, modules: moduleIds, siteIds: nil))
    }

    public func adminRemoveMember(id: UUID, organizationId: UUID) async throws { try await removeMember(id: id, organizationId: organizationId) }

    private struct AdminScreenDB: Decodable {
        let id: UUID; let name: String?; let locationId: UUID?; let orientation: String?; let appVersion: String?; let model: String?; let lastSeenAt: Date?
        enum CodingKeys: String, CodingKey { case id, name, orientation, model, locationId = "location_id", appVersion = "app_version", lastSeenAt = "last_seen_at" }
    }
    private struct LocName: Decodable { let id: UUID; let name: String }

    public func adminListScreens(organizationId: UUID) async throws -> [AdminScreenRow] {
        try await guarded {
            let org = organizationId.uuidString.lowercased()
            async let screens: [AdminScreenDB] = plainRows(client.from("screens").select("id,name,location_id,orientation,app_version,model,last_seen_at").eq("organization_id", value: org).order("name"))
            async let locations: [LocName] = plainRows(client.from("locations").select("id,name").eq("organization_id", value: org))
            let (s, l) = try await (screens, locations)
            let names = Dictionary(l.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            return s.map { AdminScreenRow(id: $0.id, name: $0.name, locationName: $0.locationId.flatMap { names[$0] }, orientation: $0.orientation, appVersion: $0.appVersion, model: $0.model, lastSeenAt: $0.lastSeenAt) }
        }
    }
}
