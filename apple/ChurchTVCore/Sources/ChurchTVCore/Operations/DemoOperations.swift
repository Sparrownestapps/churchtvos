import Foundation

// Demo mode (MockService) for the Mac app's operations, library and admin console. In memory; resets when the app restarts.
// Edits to screens are kept as an overlay (`overlayScreens`) because MockService's own screen table is private to its file.

/// Demo state that is not part of `MockContentStore`: screen edits, people, church settings, the admin console's churches.
actor DemoOpsStore {
    static let shared = DemoOpsStore()

    static let pairCode = "DEM123"
    static let tvLimit = 6

    var screenEdits: [UUID: ScreenSettings] = [:]
    var released: Set<UUID> = []
    var claimed: [ScreenInfo] = []
    var members: [Member]
    var orgName = "Grace Community Church (Demo)"
    var branding = BrandingSettings(object: [
        "primary_color": .string("#1f3a5f"), "accent_color": .string("#f59e0b"),
        "splash": .object(["enabled": .bool(true), "seconds": .number(5)]),
        "modules": .object(["kids": .object(["primary_color": .string("#2e7d5b"), "accent_color": .string("#f59e0b")])]),
        "youtube_channel_id": .string("UCdemoChannel00000000000"),
    ])
    var orgs: [AdminOrg]
    var audit: [AuditEntry]
    var orgMembers: [UUID: [Member]]

    static func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "D0D0D0D0-0000-4000-8000-0000009%05d", n))! }

    init() {
        let org = MockService.churchId
        let site1 = UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000B1")!
        let site2 = UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000B2")!
        let all = ["kids", "signage", "slides"]
        members = [
            Member(id: Self.uuid(1), organizationId: org, userId: MockService.demoUser.id, email: "demo@churchtvos.com", role: .owner, modules: all, createdAt: Date().addingTimeInterval(-90 * 86400)),
            Member(id: Self.uuid(2), organizationId: org, userId: Self.uuid(52), email: "pastor.sam@grace-demo.org", role: .admin, modules: all, createdAt: Date().addingTimeInterval(-60 * 86400)),
            Member(id: Self.uuid(3), organizationId: org, userId: Self.uuid(53), email: "kids.lead@grace-demo.org", role: .editor, modules: ["kids"], siteIds: [site1], createdAt: Date().addingTimeInterval(-30 * 86400)),
            Member(id: Self.uuid(4), organizationId: org, userId: Self.uuid(54), email: "tech.volunteer@grace-demo.org", role: .operator, modules: ["slides"], siteIds: [site1, site2], createdAt: Date().addingTimeInterval(-10 * 86400)),
            Member(id: Self.uuid(5), organizationId: org, userId: nil, email: "new.helper@grace-demo.org", role: .editor, modules: ["signage", "slides"], createdAt: Date().addingTimeInterval(-86400)),
        ]

        let now = Date()
        func ent(_ m: String, _ status: String, _ limit: Int, _ plan: String, end: Double? = nil, grace: Double? = nil) -> AdminEnt {
            let e = AdminEnt(module: m, status: status, tvLimit: limit, plan: plan, currentPeriodEnd: end.map { now.addingTimeInterval($0 * 86400) }, graceEndsAt: grace.map { now.addingTimeInterval($0 * 86400) })
            return e
        }
        func live(_ e: AdminEnt, _ s: OrgStatus) -> AdminEnt { var x = e; x.live = AdminLogic.isLive(e, s, now: now); return x }
        func make(_ n: Int, _ name: String, _ slug: String, ago: Double, status: OrgStatus = .active, reason: String? = nil, notes: String? = nil, reviewed: Bool = true,
                  owners: [String], members: Int, screens: Int, seen: Double?, media: Int, bytes: Double, songs: Int, decks: Int, lists: Int, ents: [AdminEnt], ndi: Bool = false) -> AdminOrg {
            AdminOrg(id: n == 0 ? org : Self.uuid(100 + n), name: name, slug: slug, createdAt: now.addingTimeInterval(-ago * 86400), status: status, suspendedReason: reason, adminNotes: notes,
                     reviewedAt: reviewed ? now.addingTimeInterval(-ago * 86400 + 3600) : nil, ownerEmails: owners, memberCount: members, screenCount: screens,
                     lastSeenAt: seen.map { now.addingTimeInterval(-$0 * 3600) }, mediaCount: media, storageBytes: Int64(bytes * 1_048_576), songCount: songs, deckCount: decks,
                     playlistCount: lists, entitlements: ents.map { live($0, status) }, ndiEnabled: ndi)
        }
        orgs = [
            make(0, "Grace Community Church (Demo)", "grace-demo", ago: 120, owners: ["demo@churchtvos.com"], members: 5, screens: 4, seen: 0.01, media: 18, bytes: 640, songs: 5, decks: 2, lists: 4,
                 ents: [ent("kids", "active", 6, "standard"), ent("signage", "active", 6, "standard"), ent("slides", "active", 6, "standard")]),
            make(1, "Riverside Fellowship", "riverside", ago: 3, notes: "Met at the conference. Wants to try Slides first.", reviewed: false, owners: ["office@riverside-fellowship.org"], members: 2, screens: 1, seen: 2,
                 media: 3, bytes: 48, songs: 0, decks: 1, lists: 0, ents: [ent("kids", "trialing", 2, "trial", end: 27), ent("slides", "trialing", 2, "trial", end: 27)]),
            make(2, "Hilltop Baptist", "hilltop-baptist", ago: 40, owners: ["pastor@hilltop.example"], members: 6, screens: 3, seen: 5, media: 41, bytes: 1210, songs: 22, decks: 5, lists: 7,
                 ents: [ent("kids", "trialing", 2, "trial", end: 4), ent("signage", "trialing", 2, "trial", end: 4)]),
            make(3, "St. Anne's Parish", "st-annes", ago: 200, owners: ["admin@stannes.example", "father.paul@stannes.example"], members: 9, screens: 5, seen: 0.2, media: 120, bytes: 5400, songs: 60, decks: 12, lists: 15,
                 ents: [ent("kids", "active", 10, "standard"), ent("signage", "active", 10, "standard"), ent("slides", "active", 10, "standard")]),
            make(4, "Lakeshore Community", "lakeshore", ago: 75, notes: "Trial ended with no reply to two emails.", owners: ["info@lakeshore.example"], members: 3, screens: 2, seen: 400, media: 9, bytes: 150, songs: 3, decks: 1, lists: 2,
                 ents: [ent("kids", "trialing", 2, "trial", end: -20)]),
            make(5, "Northgate Chapel", "northgate", ago: 150, status: .suspended, reason: "Unpaid invoice since August", notes: "Billing contact is the treasurer.", owners: ["treasurer@northgate.example"], members: 4, screens: 2, seen: 900,
                 media: 30, bytes: 800, songs: 12, decks: 3, lists: 5, ents: [ent("kids", "past_due", 4, "standard", grace: -10), ent("slides", "active", 4, "standard")], ndi: false),
            make(6, "Forward Church (internal)", "forward-church", ago: 365, owners: ["keith@sparrownest.com"], members: 12, screens: 8, seen: 0.05, media: 260, bytes: 9800, songs: 140, decks: 20, lists: 30,
                 ents: [ent("kids", "active", 50, "internal"), ent("signage", "active", 50, "internal"), ent("slides", "active", 50, "internal")], ndi: true),
        ]

        audit = [
            AuditEntry(id: 9, at: now.addingTimeInterval(-3600), actorEmail: "keith@sparrownest.com", organizationId: Self.uuid(101), action: "plan_insert",
                       detail: .object(["module": .string("kids"), "to": .object(["status": .string("trialing"), "tv_limit": .number(2), "plan": .string("trial")])])),
            AuditEntry(id: 8, at: now.addingTimeInterval(-86400 * 2), actorEmail: "keith@sparrownest.com", organizationId: Self.uuid(105), action: "church_suspended", detail: .object(["reason": .string("Unpaid invoice since August")])),
            AuditEntry(id: 7, at: now.addingTimeInterval(-86400 * 9), actorEmail: "keith@sparrownest.com", organizationId: Self.uuid(106), action: "ndi_enabled", detail: .object([:])),
            AuditEntry(id: 6, at: now.addingTimeInterval(-86400 * 20), actorEmail: "keith@sparrownest.com", organizationId: Self.uuid(102), action: "plan_update",
                       detail: .object(["module": .string("kids"), "from": .object(["status": .string("trialing"), "tv_limit": .number(2)]), "to": .object(["status": .string("trialing"), "tv_limit": .number(2)])])),
            AuditEntry(id: 5, at: now.addingTimeInterval(-86400 * 40), actorEmail: "keith@sparrownest.com", organizationId: Self.uuid(103), action: "church_reviewed", detail: .object([:])),
        ]
        func m(_ n: Int, _ o: UUID, _ email: String, _ role: Role, _ signedIn: Bool) -> Member {
            Member(id: Self.uuid(200 + n), organizationId: o, userId: signedIn ? Self.uuid(300 + n) : nil, email: email, role: role, modules: all)
        }
        orgMembers = [:]
        for o in orgs { orgMembers[o.id] = o.id == org ? members : [m(Int(o.id.uuidString.suffix(3)) ?? 1, o.id, o.ownerEmails.first ?? "owner@example.org", .owner, true)] }
    }

    // MARK: Screens

    func overlay(_ list: [ScreenInfo]) -> [ScreenInfo] {
        var out = list.filter { !released.contains($0.id) }.map { info -> ScreenInfo in
            guard let e = screenEdits[info.id] else { return info }
            var i = info
            i.screen.name = e.name; i.screen.locationId = e.locationId; i.screen.orientation = e.orientation.rawValue
            i.screen.defaultModule = e.defaultModule; i.screen.groupId = e.groupId
            return i
        }
        out += claimed.filter { !released.contains($0.id) }.map { info in
            guard let e = screenEdits[info.id] else { return info }
            var i = info; i.screen.name = e.name; i.screen.locationId = e.locationId; i.screen.orientation = e.orientation.rawValue; i.screen.defaultModule = e.defaultModule
            return i
        }
        return out
    }

    func settings(for list: [ScreenInfo]) -> [UUID: ScreenSettings] {
        var out: [UUID: ScreenSettings] = [:]
        for info in overlay(list) {
            let s = info.screen
            out[info.id] = screenEdits[info.id] ?? ScreenSettings(screenId: info.id, name: s.name, locationId: s.locationId,
                                                                  orientation: s.orientation.flatMap(ScreenOrientation.init(rawValue:)) ?? .landscape,
                                                                  defaultModule: s.defaultModule ?? "kids", groupId: s.groupId, autoplay: info.screen.name == "Lobby TV")
        }
        return out
    }

    func edit(_ s: ScreenSettings) { screenEdits[s.screenId] = s }
    func release(_ id: UUID) { released.insert(id); claimed.removeAll { $0.id == id } }

    func claim(code: String, location: Location?, name: String?, currentCount: Int) throws {
        let n = PairingCode.normalize(code)
        if currentCount >= Self.tvLimit { throw ChurchError("Your plan allows \(Self.tvLimit) TV(s). Remove a TV or upgrade to add more.") }
        guard n == Self.pairCode else { throw ChurchError("No TV is showing code \(n)") }
        guard !claimed.contains(where: { _ in true }) else { throw ChurchError("No TV is showing code \(n)") }   // the demo TV is claimed once
        let id = Self.uuid(900)
        let screen = Screen(id: id, organizationId: MockService.churchId, locationId: location?.id, name: name?.blankToNil ?? "New TV", orientation: "landscape",
                            defaultModule: "kids", model: "Fire TV Stick 4K", appVersion: "1.6.0", lastSeenAt: Date())
        claimed.append(ScreenInfo(screen: screen, locationName: location?.name, siteName: "Downtown Campus", timeZoneId: TimeZone.current.identifier, status: nil))
        screenEdits[id] = ScreenSettings(screenId: id, name: screen.name, locationId: location?.id)
    }

    // MARK: People

    func addMember(_ draft: AccessDraft) throws {
        let email = PeopleRules.normalizedEmail(draft.email)
        if members.contains(where: { $0.email == email }) { throw ChurchError("duplicate key value violates unique constraint \"memberships_organization_id_email_key\"") }
        members.append(Member(organizationId: MockService.churchId, email: email, role: draft.role, modules: draft.modules, siteIds: draft.siteIds, createdAt: Date()))
        members.sort { $0.email < $1.email }
    }

    func updateMember(_ id: UUID, _ draft: AccessDraft) throws {
        guard let i = members.firstIndex(where: { $0.id == id }) else { throw ChurchError("That person no longer has access here.") }
        if members[i].role == .owner, draft.role != .owner, members.filter({ $0.role == .owner }).count == 1 { throw ChurchError("A church must keep at least one owner.") }
        members[i].role = draft.role; members[i].modules = draft.modules; members[i].siteIds = draft.siteIds
    }

    func removeMember(_ id: UUID) throws {
        guard let m = members.first(where: { $0.id == id }) else { return }
        if m.role == .owner, members.filter({ $0.role == .owner }).count == 1 { throw ChurchError("A church must keep at least one owner.") }
        members.removeAll { $0.id == id }
    }

    func setOrg(name: String, branding: BrandingSettings) { orgName = name; self.branding = branding }

    // MARK: Admin

    func updateOrg(_ id: UUID, _ c: AdminOrgChange, actor: String) {
        guard let i = orgs.firstIndex(where: { $0.id == id }) else { return }
        if let s = c.status {
            orgs[i].status = s
            orgs[i].suspendedReason = s == .suspended ? c.reason : nil
            addAudit(id, s == .suspended ? "church_suspended" : "church_reactivated", detail: s == .suspended ? ["reason": .string(c.reason ?? "")] : [:], actor: actor)
            orgs[i].entitlements = orgs[i].entitlements.map { var e = $0; e.live = AdminLogic.isLive(e, s); return e }
        }
        if let n = c.notes { orgs[i].adminNotes = n }
        if let r = c.reviewed { if r { if orgs[i].reviewedAt == nil { orgs[i].reviewedAt = Date(); addAudit(id, "church_reviewed", detail: [:], actor: actor) } } else { orgs[i].reviewedAt = nil } }
        if let n = c.ndi, n != orgs[i].ndiEnabled { orgs[i].ndiEnabled = n; addAudit(id, n ? "ndi_enabled" : "ndi_disabled", detail: [:], actor: actor) }
    }

    func upsert(_ rows: [AdminEntitlementRow], actor: String) {
        for r in rows {
            guard let i = orgs.firstIndex(where: { $0.id == r.organizationId }) else { continue }
            let new = AdminEnt(module: r.module, status: r.status, tvLimit: r.tvLimit, plan: r.plan, currentPeriodEnd: r.currentPeriodEnd, graceEndsAt: r.graceEndsAt,
                               live: AdminLogic.isLive(status: r.status, currentPeriodEnd: r.currentPeriodEnd, graceEndsAt: r.graceEndsAt, orgStatus: orgs[i].status))
            func raw(_ e: AdminEnt) -> RawJSON { .object(["status": .string(e.status), "tv_limit": .number(Double(e.tvLimit)), "plan": .string(e.plan)]) }
            if let j = orgs[i].entitlements.firstIndex(where: { $0.module == r.module }) {
                addAudit(r.organizationId, "plan_update", detail: ["module": .string(r.module), "from": raw(orgs[i].entitlements[j]), "to": raw(new)], actor: actor)
                orgs[i].entitlements[j] = new
            } else {
                addAudit(r.organizationId, "plan_insert", detail: ["module": .string(r.module), "to": raw(new)], actor: actor)
                orgs[i].entitlements.append(new)
            }
        }
    }

    func deleteEntitlement(_ org: UUID, _ module: String, actor: String) {
        guard let i = orgs.firstIndex(where: { $0.id == org }), let j = orgs[i].entitlements.firstIndex(where: { $0.module == module }) else { return }
        let e = orgs[i].entitlements.remove(at: j)
        addAudit(org, "plan_delete", detail: ["module": .string(module), "from": .object(["status": .string(e.status), "tv_limit": .number(Double(e.tvLimit)), "plan": .string(e.plan)])], actor: actor)
    }

    private func addAudit(_ org: UUID, _ action: String, detail: RawObject, actor: String) {
        audit.insert(AuditEntry(id: (audit.first?.id ?? 0) + 1, at: Date(), actorEmail: actor, organizationId: org, action: action, detail: .object(detail)), at: 0)
    }
}

// MARK: - Operations

extension MockService: OperationsService {
    private static var platformAdminFlag: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoadmin") || UserDefaults.standard.bool(forKey: "demoPlatformAdmin")
    }

    public func isPlatformAdmin() async throws -> Bool { Self.platformAdminFlag }

    public func listModules(availableOnly: Bool) async throws -> [ModuleDef] {
        [ModuleDef(id: "kids", name: "Kids", sort: 1), ModuleDef(id: "signage", name: "Signage", sort: 2), ModuleDef(id: "slides", name: "Slides", sort: 3),
         ModuleDef(id: "production", name: "Production", sort: 4, available: false)].filter { !availableOnly || $0.available }
    }

    public func overlayScreens(_ screens: [ScreenInfo]) async -> [ScreenInfo] { await DemoOpsStore.shared.overlay(screens) }

    public func loadScreenSettings(organizationId: UUID) async throws -> [UUID: ScreenSettings] {
        await DemoOpsStore.shared.settings(for: try await listScreens(organizationId: organizationId))
    }

    public func updateScreen(_ settings: ScreenSettings) async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
        await DemoOpsStore.shared.edit(settings)
    }

    public func claimScreen(code: String, locationId: UUID, name: String?) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        let count = await DemoOpsStore.shared.overlay(try await listScreens(organizationId: Self.churchId)).count
        try await DemoOpsStore.shared.claim(code: code, location: store.locations.first { $0.id == locationId }, name: name, currentCount: count)
    }

    public func releaseScreen(id: UUID) async throws { await DemoOpsStore.shared.release(id) }
    public func tvLimit(organizationId: UUID) async throws -> Int? { DemoOpsStore.tvLimit }

    public func listMembers(organizationId: UUID) async throws -> [Member] {
        try await Task.sleep(nanoseconds: 120_000_000)
        return await DemoOpsStore.shared.members.sorted { $0.email < $1.email }
    }
    public func inviteMember(organizationId: UUID, draft: AccessDraft) async throws {
        if let p = PeopleRules.problem(draft, isInvite: true) { throw ChurchError(p) }
        do { try await DemoOpsStore.shared.addMember(draft) } catch let e as ChurchError { throw ChurchError(ContentErrors.friendly(e.message)) }
    }
    public func updateMember(id: UUID, draft: AccessDraft) async throws {
        if let p = PeopleRules.problem(draft, isInvite: false) { throw ChurchError(p) }
        try await DemoOpsStore.shared.updateMember(id, draft)
    }
    public func removeMember(id: UUID, organizationId: UUID) async throws { try await DemoOpsStore.shared.removeMember(id) }

    public func loadOrganization(id: UUID) async throws -> OrganizationSettings {
        let s = DemoOpsStore.shared
        return OrganizationSettings(id: id, name: await s.orgName, slug: "grace-demo", branding: await s.branding)
    }
    public func saveOrganization(id: UUID, name: String, branding: BrandingSettings) async throws {
        if let p = BrandingSettings.problem(name: name, youtubeChannelId: branding.youtubeChannelId ?? "") { throw ChurchError(p) }
        await DemoOpsStore.shared.setOrg(name: name.trimmingCharacters(in: .whitespacesAndNewlines), branding: branding)
    }
    public func uploadBrandingLogo(organizationId: UUID, fileURL: URL, contentType: String) async throws -> String {
        try await Task.sleep(nanoseconds: 300_000_000)
        return DemoMedia.url(.image, "1f3a5f", "f59e0b")
    }
    public func loadPlan(organizationId: UUID) async throws -> [PlanRow] {
        let end = Date().addingTimeInterval(86400 * 365)
        return [PlanRow(module: "kids", status: "active", tvLimit: DemoOpsStore.tvLimit, plan: "standard", currentPeriodEnd: end),
                PlanRow(module: "signage", status: "active", tvLimit: DemoOpsStore.tvLimit, plan: "standard", currentPeriodEnd: end),
                PlanRow(module: "slides", status: "trialing", tvLimit: DemoOpsStore.tvLimit, plan: "trial", currentPeriodEnd: Date().addingTimeInterval(86400 * 12))]
    }
}

// MARK: - Library

extension MockService: LibraryService {
    public func mediaUsage(organizationId: UUID, module: AppModule) async throws -> [UUID: [String]] {
        // The demo "Welcome" video is used by the Week 3 playlist, like the delete protection demo for decks and playlists.
        guard module == .kids, let used = store.media.first(where: { $0.module == "kids" && $0.kind == .video }) else { return [:] }
        return [used.id: [Self.braveList.name]]
    }

    public func renameMedia(id: UUID, organizationId: UUID, title: String) async throws {
        guard let i = store.media.firstIndex(where: { $0.id == id }) else { throw ChurchError("That file no longer exists.") }
        store.media[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func deleteMedia(_ item: MediaItem, organizationId: UUID) async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
        if let names = try await mediaUsage(organizationId: organizationId, module: item.appModule ?? .kids)[item.id], !names.isEmpty {
            throw ChurchError("\"\(item.title)\" is used in: \(names.joined(separator: ", ")). Remove it from those playlists first.")
        }
        store.media.removeAll { $0.id == item.id }
    }

    public func moveMedia(ids: [UUID], organizationId: UUID, module: AppModule, to folder: UUID?) async throws {
        for i in store.media.indices where ids.contains(store.media[i].id) && store.media[i].module == module.rawValue { store.media[i].folderId = folder }
    }

    public func createFolder(organizationId: UUID, module: AppModule, parent: UUID?, siteId: UUID?, name: String) async throws -> MediaFolder {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.folders.contains(where: { $0.module == module.rawValue && $0.parentId == parent && $0.name.lowercased() == n.lowercased() }) {
            throw ChurchError("A folder with that name already exists here.")
        }
        let f = MediaFolder(id: UUID(), module: module.rawValue, parentId: parent, name: n, siteId: siteId)
        store.folders.append(f)
        return f
    }

    public func renameFolder(id: UUID, organizationId: UUID, name: String) async throws {
        guard let i = store.folders.firstIndex(where: { $0.id == id }) else { throw ChurchError("That folder no longer exists.") }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = store.folders[i]
        if store.folders.contains(where: { $0.id != id && $0.module == f.module && $0.parentId == f.parentId && $0.name.lowercased() == n.lowercased() }) {
            throw ChurchError("A folder with that name already exists here.")
        }
        store.folders[i].name = n
    }

    public func moveFolder(id: UUID, organizationId: UUID, to parent: UUID?) async throws {
        guard let i = store.folders.firstIndex(where: { $0.id == id }) else { throw ChurchError("That folder no longer exists.") }
        // A folder cannot move into itself or one of its own sub-folders.
        var cur = parent
        while let c = cur { if c == id { throw ChurchError("A folder cannot be moved into itself.") }; cur = store.folders.first { $0.id == c }?.parentId }
        store.folders[i].parentId = parent
    }

    public func deleteFolder(id: UUID, organizationId: UUID) async throws {
        guard let f = store.folders.first(where: { $0.id == id }) else { return }
        for i in store.folders.indices where store.folders[i].parentId == id { store.folders[i].parentId = f.parentId }
        for i in store.media.indices where store.media[i].folderId == id { store.media[i].folderId = f.parentId }
        store.folders.removeAll { $0.id == id }
    }

    public func songUsage(organizationId: UUID) async throws -> [UUID: [String]] {
        guard let first = store.songs.sorted(by: { $0.title < $1.title }).first else { return [:] }
        return [first.id: [Self.braveList.name]]
    }

    public func saveSong(_ draft: SongDraft, organizationId: UUID) async throws -> Song {
        if let p = draft.problem { throw ChurchError(p) }
        let row = draft.row(organizationId: organizationId)
        if let id = draft.id, let i = store.songs.firstIndex(where: { $0.id == id }) {
            store.songs[i].title = row.title; store.songs[i].authors = row.authors; store.songs[i].ccliNumber = row.ccliNumber; store.songs[i].copyright = row.copyright
            store.songs[i].sections = row.sections; store.songs[i].arrangement = row.arrangement; store.songs[i].linesPerSlide = row.linesPerSlide; store.songs[i].updatedAt = Date()
            return store.songs[i]
        }
        let song = Song(id: UUID(), title: row.title, organizationId: Self.churchId, authors: row.authors, ccliNumber: row.ccliNumber, copyright: row.copyright,
                        sections: row.sections, arrangement: row.arrangement, linesPerSlide: row.linesPerSlide, source: row.source, createdAt: Date(), updatedAt: Date())
        store.songs.append(song)
        return song
    }

    public func insertSongs(_ drafts: [SongDraft], organizationId: UUID) async throws {
        for d in drafts { _ = try await saveSong(SongDraft(id: nil, title: d.title, authors: d.authors, ccliNumber: d.ccliNumber, copyright: d.copyright, sections: d.sections,
                                                            arrangement: d.arrangement, linesPerSlide: d.linesPerSlide, source: d.source), organizationId: organizationId) }
    }

    public func deleteSong(id: UUID, organizationId: UUID) async throws {
        if let names = try await songUsage(organizationId: organizationId)[id], let song = store.songs.first(where: { $0.id == id }) {
            throw ChurchError("\"\(song.title)\" is used in: \(names.joined(separator: ", ")). Remove it from those playlists first.")
        }
        store.songs.removeAll { $0.id == id }
    }
}

// MARK: - Admin console

extension MockService: AdminService {
    private static let demoActor = "keith@sparrownest.com"

    public func adminListOrganizations() async throws -> [AdminOrg] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return await DemoOpsStore.shared.orgs.sorted { $0.createdAt > $1.createdAt }
    }
    public func adminUpdateOrganization(_ id: UUID, change: AdminOrgChange) async throws { await DemoOpsStore.shared.updateOrg(id, change, actor: Self.demoActor) }
    public func adminUpsertEntitlements(_ rows: [AdminEntitlementRow]) async throws { await DemoOpsStore.shared.upsert(rows.map(AdminLogic.cleanedEntitlement), actor: Self.demoActor) }
    public func adminDeleteEntitlement(organizationId: UUID, module: String) async throws { await DemoOpsStore.shared.deleteEntitlement(organizationId, module, actor: Self.demoActor) }

    public func adminListAudit(organizationId: UUID?, action: String?, page: Int, pageSize: Int) async throws -> [AuditEntry] {
        let all = await DemoOpsStore.shared.audit.filter { (organizationId == nil || $0.organizationId == organizationId) && (action == nil || $0.action == action) }
        return Array(all.dropFirst(page * pageSize).prefix(pageSize + 1))
    }

    public func adminListMembers(organizationId: UUID) async throws -> [Member] { await DemoOpsStore.shared.orgMembers[organizationId] ?? [] }
    public func adminInviteMember(organizationId: UUID, email: String, role: Role, moduleIds: [String]) async throws {
        let draft = AccessDraft(email: email, role: role, modules: moduleIds)
        if let p = PeopleRules.problem(draft, isInvite: true) { throw ChurchError(p) }
        if organizationId == Self.churchId { try await DemoOpsStore.shared.addMember(draft) }
    }
    public func adminRemoveMember(id: UUID, organizationId: UUID) async throws { if organizationId == Self.churchId { try await DemoOpsStore.shared.removeMember(id) } }

    public func adminListScreens(organizationId: UUID) async throws -> [AdminScreenRow] {
        let now = Date()
        if organizationId == Self.churchId {
            return await DemoOpsStore.shared.overlay(try await listScreens(organizationId: organizationId)).map {
                AdminScreenRow(id: $0.id, name: $0.screen.name, locationName: $0.locationName, orientation: $0.screen.orientation, appVersion: $0.screen.appVersion, model: $0.screen.model, lastSeenAt: $0.screen.lastSeenAt)
            }
        }
        let org = await DemoOpsStore.shared.orgs.first { $0.id == organizationId }
        return (0..<(org?.screenCount ?? 0)).map { i in
            AdminScreenRow(id: UUID(), name: "TV \(i + 1)", locationName: ["Sanctuary", "Kids Room", "Lobby"][i % 3], orientation: "landscape", appVersion: "1.5.1", model: "Fire TV Stick 4K",
                           lastSeenAt: org?.lastSeenAt.map { $0.addingTimeInterval(Double(-i) * 60) } ?? now)
        }
    }
}
