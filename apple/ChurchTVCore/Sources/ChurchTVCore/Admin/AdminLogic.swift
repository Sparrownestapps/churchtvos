import Foundation

// Platform admin console models and rules. Port of dashboard/src/admin/logic.ts (and the shapes ChurchDetail.tsx writes).
// Only a platform administrator can read or write any of this: the database refuses everyone else.

public enum OrgStatus: String, Codable, Sendable { case active, suspended }

/// One element of `admin_list_organizations().entitlements`.
public struct AdminEnt: Codable, Hashable, Sendable {
    public var module: String
    public var status: String
    public var tvLimit: Int
    public var plan: String
    public var currentPeriodEnd: Date?
    public var graceEndsAt: Date?
    public var live: Bool

    public init(module: String, status: String, tvLimit: Int, plan: String, currentPeriodEnd: Date? = nil, graceEndsAt: Date? = nil, live: Bool = false) {
        self.module = module; self.status = status; self.tvLimit = tvLimit; self.plan = plan
        self.currentPeriodEnd = currentPeriodEnd; self.graceEndsAt = graceEndsAt; self.live = live
    }
}

/// One row of `admin_list_organizations()`.
public struct AdminOrg: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var slug: String
    public var createdAt: Date
    public var status: OrgStatus
    public var suspendedReason: String?
    public var adminNotes: String?
    public var reviewedAt: Date?
    public var ownerEmails: [String]
    public var memberCount: Int
    public var screenCount: Int
    public var lastSeenAt: Date?
    public var mediaCount: Int
    public var storageBytes: Int64
    public var songCount: Int
    public var deckCount: Int
    public var playlistCount: Int
    public var entitlements: [AdminEnt]
    /// EXPERIMENTAL NDI switch (`organizations.ndi_enabled`).
    public var ndiEnabled: Bool

    public init(id: UUID, name: String, slug: String, createdAt: Date, status: OrgStatus = .active, suspendedReason: String? = nil, adminNotes: String? = nil,
                reviewedAt: Date? = nil, ownerEmails: [String] = [], memberCount: Int = 0, screenCount: Int = 0, lastSeenAt: Date? = nil, mediaCount: Int = 0,
                storageBytes: Int64 = 0, songCount: Int = 0, deckCount: Int = 0, playlistCount: Int = 0, entitlements: [AdminEnt] = [], ndiEnabled: Bool = false) {
        self.id = id; self.name = name; self.slug = slug; self.createdAt = createdAt; self.status = status; self.suspendedReason = suspendedReason
        self.adminNotes = adminNotes; self.reviewedAt = reviewedAt; self.ownerEmails = ownerEmails; self.memberCount = memberCount
        self.screenCount = screenCount; self.lastSeenAt = lastSeenAt; self.mediaCount = mediaCount; self.storageBytes = storageBytes
        self.songCount = songCount; self.deckCount = deckCount; self.playlistCount = playlistCount; self.entitlements = entitlements; self.ndiEnabled = ndiEnabled
    }

    // Decoded with `ChurchJSON.decoder()` (snake_case keys). Counts may arrive as numbers or strings (bigint); lists may be null.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func int(_ k: Keys) -> Int {
            if let n = try? c.decode(Int.self, forKey: k) { return n }
            if let s = try? c.decode(String.self, forKey: k), let n = Int(s) { return n }
            if let d = try? c.decode(Double.self, forKey: k) { return Int(d) }
            return 0
        }
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        slug = try c.decode(String.self, forKey: .slug)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        status = (try? c.decode(OrgStatus.self, forKey: .status)) ?? .active
        suspendedReason = try c.decodeIfPresent(String.self, forKey: .suspendedReason)
        adminNotes = try c.decodeIfPresent(String.self, forKey: .adminNotes)
        reviewedAt = try c.decodeIfPresent(Date.self, forKey: .reviewedAt)
        ownerEmails = (try? c.decodeIfPresent([String].self, forKey: .ownerEmails)) ?? []
        memberCount = int(.memberCount); screenCount = int(.screenCount); mediaCount = int(.mediaCount)
        songCount = int(.songCount); deckCount = int(.deckCount); playlistCount = int(.playlistCount)
        storageBytes = Int64(int(.storageBytes))
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        entitlements = (try? c.decodeIfPresent([AdminEnt].self, forKey: .entitlements)) ?? []
        ndiEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .ndiEnabled)) ?? false
    }

    private enum Keys: String, CodingKey {
        case id, name, slug, createdAt, status, suspendedReason, adminNotes, reviewedAt, ownerEmails, memberCount, screenCount, lastSeenAt
        case mediaCount, storageBytes, songCount, deckCount, playlistCount, entitlements, ndiEnabled
    }
}

/// A row of `admin_audit_log`.
public struct AuditEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var at: Date
    public var actorEmail: String?
    public var organizationId: UUID?
    public var action: String
    public var detail: RawJSON?
    public init(id: Int, at: Date, actorEmail: String? = nil, organizationId: UUID? = nil, action: String, detail: RawJSON? = nil) {
        self.id = id; self.at = at; self.actorEmail = actorEmail; self.organizationId = organizationId; self.action = action; self.detail = detail
    }
}

/// What `admin_update_organization` should change. Only set the fields that change (nil = leave alone).
public struct AdminOrgChange: Equatable, Sendable {
    public var status: OrgStatus?
    public var reason: String?
    public var notes: String?
    public var reviewed: Bool?
    public var ndi: Bool?
    public init(status: OrgStatus? = nil, reason: String? = nil, notes: String? = nil, reviewed: Bool? = nil, ndi: Bool? = nil) {
        self.status = status; self.reason = reason; self.notes = notes; self.reviewed = reviewed; self.ndi = ndi
    }
}

/// Params of `rpc('admin_update_organization')`: only the keys that are set are sent.
public struct AdminUpdateParams: Encodable, Equatable, Sendable {
    public var org: UUID
    public var change: AdminOrgChange
    public init(org: UUID, change: AdminOrgChange) { self.org = org; self.change = change }
    enum CodingKeys: String, CodingKey { case pOrg = "p_org", pStatus = "p_status", pReason = "p_reason", pNotes = "p_notes", pReviewed = "p_reviewed", pNdi = "p_ndi" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(org.uuidString.lowercased(), forKey: .pOrg)
        try c.encodeIfPresent(change.status?.rawValue, forKey: .pStatus)
        try c.encodeIfPresent(change.reason, forKey: .pReason)
        try c.encodeIfPresent(change.notes, forKey: .pNotes)
        try c.encodeIfPresent(change.reviewed, forKey: .pReviewed)
        try c.encodeIfPresent(change.ndi, forKey: .pNdi)
    }
}

/// A plan row written with `entitlements.upsert`.
public struct AdminEntitlementRow: Encodable, Equatable, Sendable {
    public var organizationId: UUID
    public var module: String
    public var status: String
    public var tvLimit: Int
    public var plan: String
    public var currentPeriodEnd: Date?
    public var graceEndsAt: Date?

    public init(organizationId: UUID, module: String, status: String, tvLimit: Int, plan: String, currentPeriodEnd: Date? = nil, graceEndsAt: Date? = nil) {
        self.organizationId = organizationId; self.module = module; self.status = status; self.tvLimit = tvLimit; self.plan = plan
        self.currentPeriodEnd = currentPeriodEnd; self.graceEndsAt = graceEndsAt
    }

    enum CodingKeys: String, CodingKey {
        case module, status, plan
        case organizationId = "organization_id", tvLimit = "tv_limit", currentPeriodEnd = "current_period_end", graceEndsAt = "grace_ends_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(organizationId.uuidString.lowercased(), forKey: .organizationId)
        try c.encode(module, forKey: .module)
        try c.encode(status, forKey: .status)
        try c.encode(tvLimit, forKey: .tvLimit)
        try c.encode(plan, forKey: .plan)
        try c.encode(currentPeriodEnd.map(ChurchJSON.formatTimestamp), forKey: .currentPeriodEnd)   // explicit nulls: clearing a date must reach the database
        try c.encode(graceEndsAt.map(ChurchJSON.formatTimestamp), forKey: .graceEndsAt)
    }
}

/// One TV in a church, as the console lists it.
public struct AdminScreenRow: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String?
    public var locationName: String?
    public var orientation: String?
    public var appVersion: String?
    public var model: String?
    public var lastSeenAt: Date?
    public init(id: UUID, name: String?, locationName: String?, orientation: String?, appVersion: String?, model: String?, lastSeenAt: Date?) {
        self.id = id; self.name = name; self.locationName = locationName; self.orientation = orientation
        self.appVersion = appVersion; self.model = model; self.lastSeenAt = lastSeenAt
    }
    public func isOnline(now: Date = Date()) -> Bool { ScreenHealth.isOnline(lastSeen: lastSeenAt, now: now) }
}

// MARK: - Rules

public enum AdminLogic {
    public static let day: TimeInterval = 86_400

    /// Same rule as the database `entitlement_live` plus the church status.
    public static func isLive(status: String, currentPeriodEnd: Date?, graceEndsAt: Date?, orgStatus: OrgStatus, now: Date = Date()) -> Bool {
        PlanRow(module: "", status: status, tvLimit: 0, plan: "", currentPeriodEnd: currentPeriodEnd, graceEndsAt: graceEndsAt)
            .isLive(churchSuspended: orgStatus == .suspended, now: now)
    }

    public static func isLive(_ e: AdminEnt, _ status: OrgStatus, now: Date = Date()) -> Bool {
        isLive(status: e.status, currentPeriodEnd: e.currentPeriodEnd, graceEndsAt: e.graceEndsAt, orgStatus: status, now: now)
    }

    /// Whole days from now (rounded up), nil without a date.
    public static func daysLeft(_ date: Date?, now: Date = Date()) -> Int? { date.map { Int(ceil($0.timeIntervalSince(now) / day)) } }

    /// "3 days ago" / "in 4 days", whole days.
    public static func relDays(_ date: Date, now: Date = Date()) -> String {
        let d = Int((now.timeIntervalSince(date) / day).rounded())
        if d == 0 { return "today" }
        return d > 0 ? "\(d) day\(d == 1 ? "" : "s") ago" : "in \(-d) day\(d == -1 ? "" : "s")"
    }

    public enum Tone: String, Sendable { case ok, warn, bad, off }

    /// Plain-words label for one module's plan, for example "Live trial 12d left".
    public static func planChip(_ e: AdminEnt, _ status: OrgStatus, now: Date = Date()) -> (text: String, tone: Tone) {
        let live = isLive(e, status, now: now)
        switch e.status {
        case "trialing":
            let d = daysLeft(e.currentPeriodEnd, now: now)
            if live { return (d.map { "Live trial \(max($0, 0))d left" } ?? "Live trial", (d ?? 99) <= 7 ? .warn : .ok) }
            return ("Expired", .bad)
        case "active": return (e.plan == "internal" ? "Active internal" : "Active", live ? .ok : .off)
        case "past_due": return ("Past due", live ? .warn : .bad)
        default: return ("Canceled", .off)
        }
    }

    public enum Bucket: String, CaseIterable, Identifiable, Sendable {
        case all, new, trial, paid, expired, suspended
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .all: return "All"
            case .new: return "New (unreviewed)"
            case .trial: return "Trial"
            case .paid: return "Active paid or internal"
            case .expired: return "Expired or no plan"
            case .suspended: return "Suspended"
            }
        }
    }

    public static func hasLive(_ o: AdminOrg, now: Date = Date()) -> Bool { o.entitlements.contains { isLive($0, o.status, now: now) } }
    public static func liveTrials(_ o: AdminOrg, now: Date = Date()) -> [AdminEnt] { o.entitlements.filter { $0.status == "trialing" && isLive($0, o.status, now: now) } }
    public static func trialEndingSoon(_ o: AdminOrg, now: Date = Date()) -> Bool {
        o.status == .active && liveTrials(o, now: now).contains { e in e.currentPeriodEnd.map { $0.timeIntervalSince(now) <= 7 * day } ?? false }
    }

    public static func inBucket(_ o: AdminOrg, _ b: Bucket, now: Date = Date()) -> Bool {
        switch b {
        case .all: return true
        case .new: return o.reviewedAt == nil
        case .suspended: return o.status == .suspended
        case .trial: return o.status == .active && !liveTrials(o, now: now).isEmpty
        case .paid: return o.status == .active && o.entitlements.contains { $0.status == "active" && isLive($0, o.status, now: now) }
        case .expired: return o.status == .active && !hasLive(o, now: now)
        }
    }

    /// The TV limit the pairing check uses: the largest limit among live plans (0 if none).
    public static func tvLimit(_ o: AdminOrg, now: Date = Date()) -> Int {
        o.entitlements.reduce(0) { isLive($1, o.status, now: now) ? max($0, $1.tvLimit) : $0 }
    }

    // MARK: Search, sort, stats

    public enum SortKey: String, CaseIterable, Identifiable, Sendable {
        case created, name, seen, media, members
        public var id: String { rawValue }
        public var title: String {
            switch self { case .created: return "Signed up"; case .name: return "Name"; case .seen: return "Last TV seen"; case .media: return "Media size"; case .members: return "Members" }
        }
    }

    /// Search (name, short name, owner email), bucket filter, then sort.
    public static func rows(_ orgs: [AdminOrg], search: String, bucket: Bucket, sort: SortKey, descending: Bool, now: Date = Date()) -> [AdminOrg] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = orgs.filter { o in
            inBucket(o, bucket, now: now) && (needle.isEmpty || o.name.lowercased().contains(needle) || o.slug.lowercased().contains(needle)
                                              || o.ownerEmails.contains { $0.lowercased().contains(needle) })
        }
        func less(_ a: AdminOrg, _ b: AdminOrg) -> Bool {
            switch sort {
            case .created: return a.createdAt < b.createdAt
            case .name: return a.name.lowercased() < b.name.lowercased()
            case .seen: return (a.lastSeenAt ?? .distantPast) < (b.lastSeenAt ?? .distantPast)
            case .media: return a.storageBytes < b.storageBytes
            case .members: return a.memberCount < b.memberCount
            }
        }
        return list.sorted { descending ? less($1, $0) : less($0, $1) }
    }

    public struct Stats: Equatable, Sendable {
        public var total = 0, fresh = 0, ending = 0, expired = 0, suspended = 0, tvs = 0
        public var bytes: Int64 = 0
    }

    public static func stats(_ orgs: [AdminOrg], now: Date = Date()) -> Stats {
        Stats(total: orgs.count, fresh: orgs.filter { $0.reviewedAt == nil }.count, ending: orgs.filter { trialEndingSoon($0, now: now) }.count,
              expired: orgs.filter { $0.status == .active && !hasLive($0, now: now) }.count, suspended: orgs.filter { $0.status == .suspended }.count,
              tvs: orgs.reduce(0) { $0 + $1.screenCount }, bytes: orgs.reduce(0) { $0 + $1.storageBytes })
    }

    // MARK: Quick plan presets

    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case trial, extend, `internal`, standard, cancel
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .trial: return "Start 30-day trial (2 TVs)"
            case .extend: return "Extend trial by 14 days"
            case .internal: return "Free internal plan (50 TVs)"
            case .standard: return "Standard (10 TVs)"
            case .cancel: return "Cancel plan"
            }
        }
    }

    /// The row a preset would write for one module (nil = leave this module alone).
    public static func applyPreset(_ preset: Preset, orgId: UUID, module: String, current cur: AdminEnt?, now: Date = Date()) -> AdminEntitlementRow? {
        func row(status: String, limit: Int, plan: String, end: Date?, grace: Date?) -> AdminEntitlementRow {
            AdminEntitlementRow(organizationId: orgId, module: module, status: status, tvLimit: limit, plan: plan, currentPeriodEnd: end, graceEndsAt: grace)
        }
        switch preset {
        case .trial: return row(status: "trialing", limit: 2, plan: "trial", end: now.addingTimeInterval(30 * day), grace: nil)
        case .extend:
            if cur?.status == "active" { return nil }   // paid or internal plans have no trial to extend
            let from = max(now, cur?.currentPeriodEnd ?? now)
            let limit = (cur?.tvLimit ?? 0) == 0 ? 2 : cur!.tvLimit
            return row(status: "trialing", limit: limit, plan: cur?.plan ?? "trial", end: from.addingTimeInterval(14 * day), grace: nil)
        case .internal: return row(status: "active", limit: 50, plan: "internal", end: nil, grace: nil)
        case .standard: return row(status: "active", limit: 10, plan: "standard", end: nil, grace: nil)
        case .cancel:
            guard let cur else { return nil }
            return row(status: "canceled", limit: cur.tvLimit, plan: cur.plan, end: cur.currentPeriodEnd, grace: cur.graceEndsAt)
        }
    }

    // MARK: Audit in plain words

    public static let auditActions = ["plan_insert", "plan_update", "plan_delete", "church_suspended", "church_reactivated", "church_reviewed", "ndi_enabled", "ndi_disabled"]

    private static func snap(_ v: RawJSON?) -> String {
        guard let o = v?.objectValue else { return "" }
        let limit = o["tv_limit"]?.intValue ?? 0
        var end = ""
        if let s = o["current_period_end"]?.stringValue, let d = ChurchJSON.parseTimestamp(s) { end = " until \(d.formatted(date: .abbreviated, time: .omitted))" }
        return "\(o["status"]?.stringValue ?? "?") \(limit) TV\(limit == 1 ? "" : "s")\(end)"
    }

    public static func describeAudit(_ a: AuditEntry, moduleName: (String) -> String) -> String {
        let d = a.detail?.objectValue ?? [:]
        let module = moduleName(d["module"]?.stringValue ?? "?")
        switch a.action {
        case "plan_insert": return "\(module): added \(snap(d["to"]))"
        case "plan_update": return "\(module): \(snap(d["from"])) -> \(snap(d["to"]))"
        case "plan_delete": return "\(module): removed (was \(snap(d["from"])))"
        case "church_suspended": return "Suspended" + (d["reason"]?.stringValue.flatMap { $0.isEmpty ? nil : ": \($0)" } ?? "")
        case "church_reactivated": return "Reactivated"
        case "church_reviewed": return "Marked reviewed"
        case "ndi_enabled": return "Experimental NDI sources switched ON"
        case "ndi_disabled": return "Experimental NDI sources switched OFF"
        default: return a.action
        }
    }

    /// Validation for the entitlement editor ("Add" / "Save"): the website clamps the TV limit to a whole number >= 0 and defaults the plan name.
    public static func cleanedEntitlement(_ row: AdminEntitlementRow) -> AdminEntitlementRow {
        var r = row
        r.tvLimit = max(0, r.tvLimit)
        r.plan = r.plan.trimmingCharacters(in: .whitespacesAndNewlines).blankToNil ?? "standard"
        return r
    }

    /// Entitlement statuses the editor offers.
    public static let statuses = ["trialing", "active", "past_due", "canceled"]

    /// End of that local day (the website's `fromDateInput` stores 23:59:59 local).
    public static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }
}
