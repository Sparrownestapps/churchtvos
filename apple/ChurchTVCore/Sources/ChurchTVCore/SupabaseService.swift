import Foundation
import Supabase

/// The real back end. Sessions are stored in the Keychain by the SDK's default storage on Apple platforms.
public final class SupabaseService: ChurchService, @unchecked Sendable {
    let client: SupabaseClient
    private let decoder = ChurchJSON.decoder()

    public var isDemo: Bool { false }

    /// Value written to `push_devices.platform` ('ios' for the iPhone/iPad app, 'macos' for the Mac app).
    private let pushPlatform: String

    /// - Parameters:
    ///   - pushPlatform: `push_devices.platform` value for this app.
    ///   - autoRefreshToken: leave `true` for apps that own their sign-in. The Mac app turns it off because the website in its
    ///     web view owns the refresh token (two clients refreshing the same rotating token would sign the website out).
    public init(pushPlatform: String = "ios", autoRefreshToken: Bool = true) {
        self.pushPlatform = pushPlatform
        client = SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabasePublishableKey,
            options: SupabaseClientOptions(auth: .init(autoRefreshToken: autoRefreshToken, emitLocalSessionAsInitialSession: true))
        )
    }

    /// Adopts a session created elsewhere (the Mac app reads it from the website). The SDK stores it in the Keychain.
    public func setSession(accessToken: String, refreshToken: String) async throws -> SessionUser {
        try await guarded {
            let session = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
            return SessionUser(id: session.user.id, email: session.user.email ?? "")
        }
    }

    // MARK: Helpers

    /// Runs a call and turns SDK errors into readable `ChurchError`s (server "raise exception" texts pass through).
    func guarded<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() }
        catch let e as PostgrestError { throw ChurchError(e.message) }
        catch let e as AuthError { throw ChurchError(Self.authMessage(e)) }
        catch let e as ChurchError { throw e }
        catch { throw ChurchError(Formatting.message(for: error)) }
    }

    private static func authMessage(_ e: AuthError) -> String {
        let text = e.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") { return "That email and password do not match." }
        return text
    }

    func rows<T: Decodable>(_ builder: PostgrestBuilder, as type: T.Type = T.self) async throws -> [T] {
        let response = try await builder.execute()
        do { return try decoder.decode([T].self, from: response.data) }
        catch { throw ChurchError("The server sent something unexpected (\(type)). Update the app and try again.") }
    }

    private func currentUserId() async throws -> UUID {
        let session = try await client.auth.session
        return session.user.id
    }

    // MARK: Session

    public func restoreSession() async -> SessionUser? {
        guard let session = try? await client.auth.session else { return nil }
        return SessionUser(id: session.user.id, email: session.user.email ?? "")
    }

    public func signIn(email: String, password: String) async throws -> SessionUser {
        try await guarded {
            let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            return SessionUser(id: session.user.id, email: session.user.email ?? email)
        }
    }

    public func signOut() async {
        try? await client.auth.signOut()
    }

    // MARK: Churches

    private struct ModuleRow: Decodable { let id: String; let available: Bool }

    public func loadChurches() async throws -> [ChurchAccess] {
        try await guarded {
            let uid = try await currentUserId()
            // `ndi_enabled` (experimental NDI flag) needs migration 20261023000001; fall back to the old columns if it is not applied yet.
            let userId = uid.uuidString.lowercased()
            let memberships: [Membership]
            do {
                memberships = try await rows(
                    client.from("memberships")
                        .select("id,organization_id,role,modules,site_ids,organizations(id,name,slug,ndi_enabled)")
                        .eq("user_id", value: userId)
                )
            } catch {
                memberships = try await rows(
                    client.from("memberships")
                        .select("id,organization_id,role,modules,site_ids,organizations(id,name,slug)")
                        .eq("user_id", value: userId)
                )
            }
            guard !memberships.isEmpty else { return [] }
            let orgIds = memberships.map { $0.organizationId.uuidString.lowercased() }
            let entitlements: [EntitlementRow] = try await rows(
                client.from("entitlements").select("organization_id,module,status").in("organization_id", values: orgIds)
            )
            let available: [ModuleRow] = (try? await rows(client.from("modules").select("id,available"))) ?? []
            let availableIds = Set(available.filter(\.available).map(\.id))

            return memberships.compactMap { m -> ChurchAccess? in
                guard let org = m.organizations else { return nil }
                let usable = Set(entitlements.filter { $0.organizationId == m.organizationId && Entitlement(module: $0.module, status: $0.status).isUsable }.map(\.module))
                let mods = AppModule.allCases.filter {
                    m.modules.contains($0.rawValue) && usable.contains($0.rawValue) && (availableIds.isEmpty || availableIds.contains($0.rawValue))
                }
                return ChurchAccess(organization: org, role: m.role, modules: mods, siteIds: m.siteIds)
            }.sorted { $0.organization.name.localizedCaseInsensitiveCompare($1.organization.name) == .orderedAscending }
        }
    }

    private struct EntitlementRow: Decodable { let organizationId: UUID; let module: String; let status: String }

    // MARK: Screens

    public func listScreens(organizationId: UUID) async throws -> [ScreenInfo] {
        try await guarded {
            let org = organizationId.uuidString.lowercased()
            async let screensQ: [Screen] = rows(
                client.from("screens")
                    .select("id,organization_id,location_id,group_id,name,orientation,default_module,model,app_version,last_seen_at")
                    .eq("organization_id", value: org).order("name"))
            async let locationsQ: [Location] = rows(client.from("locations").select("id,name,site_id").eq("organization_id", value: org))
            async let sitesQ: [Site] = rows(client.from("sites").select("id,name,timezone").eq("organization_id", value: org))
            async let statusQ = fetchStatuses(organizationId: organizationId)
            let (screens, locations, sites, statuses) = try await (screensQ, locationsQ, sitesQ, statusQ)
            let locationsById = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
            let sitesById = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })
            return screens.map { s in
                let loc = s.locationId.flatMap { locationsById[$0] }
                let site = loc?.siteId.flatMap { sitesById[$0] }
                return ScreenInfo(screen: s, locationName: loc?.name, siteName: site?.name, timeZoneId: site?.timezone, status: statuses[s.id])
            }
        }
    }

    public func fetchStatuses(organizationId: UUID) async throws -> [UUID: ScreenStatus] {
        try await guarded {
            let list: [ScreenStatus] = try await rows(
                client.from("screen_status").select().eq("organization_id", value: organizationId.uuidString.lowercased()))
            return Dictionary(list.map { ($0.screenId, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    // MARK: Remote control

    public func send(_ command: RemoteCommand, to screenId: UUID) async throws {
        if let problem = command.validationError { throw ChurchError(problem) }
        try await guarded {
            _ = try await client.rpc("send_screen_command", params: SendCommandParams(screenId: screenId, command: command)).execute()
        }
    }

    // MARK: Content

    public func playNowItems(organizationId: UUID, modules: [AppModule]) async throws -> [PlayNowItem] {
        try await guarded {
            let org = organizationId.uuidString.lowercased()
            var items: [PlayNowItem] = []
            if modules.contains(.slides) {
                let decks: [Deck] = try await rows(client.from("decks").select("id,name").eq("organization_id", value: org).order("name"))
                items += decks.map { PlayNowItem(kind: .deck, refId: $0.id, name: $0.name) }
            }
            if modules.contains(.kids) {
                let lists: [PlaylistRef] = try await rows(client.from("playlists").select("id,name").eq("organization_id", value: org).order("name"))
                items += lists.map { PlayNowItem(kind: .playlist, refId: $0.id, name: $0.name) }
            }
            return items
        }
    }

    private struct RuleRow: Decodable { let id: UUID; let screenId: UUID?; let groupId: UUID?; let module: String; let days: [Int]; let startTime: String; let endTime: String }
    private struct OccurrenceParams: Encodable { let pOrg: String; let pFrom: Date; let pTo: Date
        enum CodingKeys: String, CodingKey { case pOrg = "p_org", pFrom = "p_from", pTo = "p_to" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pOrg, forKey: .pOrg)
            try c.encode(ChurchJSON.formatTimestamp(pFrom), forKey: .pFrom)
            try c.encode(ChurchJSON.formatTimestamp(pTo), forKey: .pTo)
        }
    }

    public func schedule(organizationId: UUID, screens: [ScreenInfo], modules: [AppModule], now: Date) async throws -> [ScheduleEntry] {
        try await guarded {
            guard !screens.isEmpty else { return [] }
            let org = organizationId.uuidString.lowercased()
            // One window for the query: from the earliest local midnight to the latest next midnight across the screens' time zones.
            let bounds = screens.map { ScheduleBuilder.dayBounds(now: now, timeZone: $0.timeZone) }
            let from = bounds.map(\.0).min() ?? now, to = bounds.map(\.1).max() ?? now.addingTimeInterval(86400)
            let fromS = ChurchJSON.formatTimestamp(from), toS = ChurchJSON.formatTimestamp(to)

            var entries: [ScheduleEntry] = []
            let byLocation = Dictionary(grouping: screens.filter { $0.screen.locationId != nil }, by: { $0.screen.locationId! })
            let names = try await playNowItems(organizationId: organizationId, modules: modules)
            let deckNames = Dictionary(uniqueKeysWithValues: names.filter { $0.kind == .deck }.map { ($0.refId, $0.name) })
            let listNames = Dictionary(uniqueKeysWithValues: names.filter { $0.kind == .playlist }.map { ($0.refId, $0.name) })

            if modules.contains(.slides) {
                let oneOff: [DeckScheduleRow] = try await rows(
                    client.from("deck_schedules").select("id,location_id,deck_id,starts_at,ends_at")
                        .eq("organization_id", value: org).lt("starts_at", value: toS)
                        .or("ends_at.is.null,ends_at.gt.\(fromS)"))
                for r in oneOff {
                    for s in byLocation[r.locationId] ?? [] {
                        entries.append(ScheduleEntry(id: "d-\(r.id)-\(s.id)", screenId: s.id, module: .slides, title: deckNames[r.deckId] ?? "Deck",
                                                     starts: r.startsAt, ends: r.endsAt, source: .oneOff))
                    }
                }
                let occ: [OccurrenceRow] = try await rows(try client.rpc("deck_series_occurrences", params: OccurrenceParams(pOrg: org, pFrom: from, pTo: to)))
                for r in occ {
                    for s in byLocation[r.locationId] ?? [] {
                        entries.append(ScheduleEntry(id: "ds-\(r.seriesId)-\(r.startsAt.timeIntervalSince1970)-\(s.id)", screenId: s.id, module: .slides,
                                                     title: r.deckId.flatMap { deckNames[$0] } ?? "Deck", starts: r.startsAt, ends: r.endsAt, source: .repeating))
                    }
                }
            }
            if modules.contains(.kids) {
                let oneOff: [KidsScheduleRow] = try await rows(
                    client.from("schedules").select("id,location_id,playlist_id,starts_at,ends_at")
                        .eq("organization_id", value: org).lt("starts_at", value: toS)
                        .or("ends_at.is.null,ends_at.gt.\(fromS)"))
                for r in oneOff {
                    for s in byLocation[r.locationId] ?? [] {
                        entries.append(ScheduleEntry(id: "k-\(r.id)-\(s.id)", screenId: s.id, module: .kids, title: listNames[r.playlistId] ?? "Playlist",
                                                     starts: r.startsAt, ends: r.endsAt, source: .oneOff))
                    }
                }
                let occ: [OccurrenceRow] = try await rows(try client.rpc("kids_series_occurrences", params: OccurrenceParams(pOrg: org, pFrom: from, pTo: to)))
                for r in occ {
                    for s in byLocation[r.locationId] ?? [] {
                        entries.append(ScheduleEntry(id: "ks-\(r.seriesId)-\(r.startsAt.timeIntervalSince1970)-\(s.id)", screenId: s.id, module: .kids,
                                                     title: r.playlistId.flatMap { listNames[$0] } ?? "Playlist", starts: r.startsAt, ends: r.endsAt, source: .repeating))
                    }
                }
            }

            // Which module a screen runs at which time of day (screen_schedules), for today's weekday.
            let rules: [RuleRow] = (try? await rows(client.from("screen_schedules").select("id,screen_id,group_id,module,days,start_time,end_time").eq("organization_id", value: org))) ?? []
            for s in screens {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = s.timeZone
                let weekday = cal.component(.weekday, from: now) - 1   // 0 = Sunday, like the database
                let (dayStart, _) = ScheduleBuilder.dayBounds(now: now, timeZone: s.timeZone)
                for r in rules where (r.screenId == s.id || (r.groupId != nil && r.groupId == s.screen.groupId)) && r.days.contains(weekday) {
                    guard let m = AppModule(rawValue: r.module),
                          let a = ScheduleBuilder.time(r.startTime, on: dayStart, calendar: cal),
                          let b = ScheduleBuilder.time(r.endTime, on: dayStart, calendar: cal) else { continue }
                    entries.append(ScheduleEntry(id: "r-\(r.id)-\(s.id)", screenId: s.id, module: m, title: "Runs \(m.displayName)", starts: a, ends: b, source: .moduleRule))
                }
            }
            return ScheduleBuilder.today(entries, screens: screens, now: now)
        }
    }

    // MARK: Media

    public func mediaFolders(organizationId: UUID, module: AppModule) async throws -> [MediaFolder] {
        try await guarded {
            try await rows(client.from("media_folders").select("id,module,parent_id,name,site_id")
                .eq("organization_id", value: organizationId.uuidString.lowercased())
                .eq("module", value: module.rawValue).order("name"))
        }
    }

    public func uploadMedia(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await uploadMediaItem(request, progress: progress)
    }

    public func uploadMediaItem(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> MediaItem? {
        try await guarded {
            progress(0.02)
            let path = MediaPath.make(organizationId: request.organizationId, filename: request.filename)
            let bucket = client.storage.from(Config.mediaBucket)
            // The SDK's upload has no byte-level progress callback, so progress here is stage based (see README).
            _ = try await bucket.upload(path, fileURL: request.fileURL, options: FileOptions(cacheControl: "3600", contentType: request.contentType, upsert: false))
            progress(0.9)
            let publicURL = try bucket.getPublicURL(path: path)
            let row = NewMediaRow(organizationId: request.organizationId, module: request.module.rawValue, title: request.title,
                                  kind: request.kind, storagePath: path, url: publicURL.absoluteString, sizeBytes: request.sizeBytes, folderId: request.folderId)
            let inserted: [MediaItem]
            do {
                let response = try await client.from("media").insert(row).select(SupabaseService.mediaColumns).execute()
                inserted = (try? ContentJSON.decoder().decode([MediaItem].self, from: response.data)) ?? []
            } catch {
                // Do not leave an orphan file behind when the database refuses the row.
                _ = try? await bucket.remove(paths: [path])
                throw error
            }
            progress(1)
            return inserted.first
        }
    }

    // MARK: Push

    private struct PushDeviceRow: Encodable {
        let userId: UUID; let platform: String; let token: String; let environment: String; let lastSeenAt: String
        enum CodingKeys: String, CodingKey { case userId = "user_id", platform, token, environment, lastSeenAt = "last_seen_at" }
    }

    public func registerPushToken(_ token: String, environment: PushEnvironment) async throws {
        try await guarded {
            let uid = try await currentUserId()
            let row = PushDeviceRow(userId: uid, platform: pushPlatform, token: token, environment: environment.rawValue, lastSeenAt: ChurchJSON.formatTimestamp(Date()))
            _ = try await client.from("push_devices").upsert(row, onConflict: "user_id,token").execute()
        }
    }

    public func removePushToken(_ token: String) async throws {
        try await guarded {
            let uid = try await currentUserId()
            _ = try await client.from("push_devices").delete().eq("user_id", value: uid.uuidString.lowercased()).eq("token", value: token).execute()
        }
    }

    private struct PrefRow: Codable { let organizationId: UUID?; let offlineAlerts: Bool }
    private struct PrefUpsert: Encodable {
        let userId: UUID; let organizationId: UUID; let offlineAlerts: Bool
        enum CodingKeys: String, CodingKey { case userId = "user_id", organizationId = "organization_id", offlineAlerts = "offline_alerts" }
    }

    public func offlineAlertsEnabled(organizationId: UUID) async throws -> Bool {
        try await guarded {
            let uid = try await currentUserId()
            let list: [PrefRow] = try await rows(client.from("notification_prefs").select("organization_id,offline_alerts")
                .eq("user_id", value: uid.uuidString.lowercased()).eq("organization_id", value: organizationId.uuidString.lowercased()))
            return list.first?.offlineAlerts ?? true   // the table default is true
        }
    }

    public func setOfflineAlerts(organizationId: UUID, enabled: Bool) async throws {
        try await guarded {
            let uid = try await currentUserId()
            _ = try await client.from("notification_prefs")
                .upsert(PrefUpsert(userId: uid, organizationId: organizationId, offlineAlerts: enabled), onConflict: "user_id,organization_id").execute()
        }
    }
}
