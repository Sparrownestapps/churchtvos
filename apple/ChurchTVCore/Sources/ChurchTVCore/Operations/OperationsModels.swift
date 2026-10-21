import Foundation

// Models and pure rules for the Mac app's native operations: screens, people, church settings and branding.
// Everything here mirrors the website (dashboard/src/pages/ScreensPage.tsx, PeoplePage.tsx, SettingsPage.tsx, BrandingEditor.tsx).

// MARK: - Screens

public enum ScreenOrientation: String, Codable, CaseIterable, Sendable, Identifiable {
    case landscape, portrait
    case portraitFlipped = "portrait_flipped"
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        case .portraitFlipped: return "Portrait (flipped)"
        }
    }
}

/// The editable columns of a `screens` row that `Screen` does not carry (autoplay, signage default playlist).
public struct ScreenSettings: Hashable, Sendable {
    public var screenId: UUID
    public var name: String?
    public var locationId: UUID?
    public var orientation: ScreenOrientation
    /// A module id ('kids', 'signage', 'slides') or "off" (black screen).
    public var defaultModule: String
    public var groupId: UUID?
    public var signageDefaultPlaylistId: UUID?
    public var autoplay: Bool

    public init(screenId: UUID, name: String? = nil, locationId: UUID? = nil, orientation: ScreenOrientation = .landscape,
                defaultModule: String = "kids", groupId: UUID? = nil, signageDefaultPlaylistId: UUID? = nil, autoplay: Bool = false) {
        self.screenId = screenId; self.name = name; self.locationId = locationId; self.orientation = orientation
        self.defaultModule = defaultModule; self.groupId = groupId; self.signageDefaultPlaylistId = signageDefaultPlaylistId; self.autoplay = autoplay
    }

    /// The row the website writes ("Save changes" on a screen card): empty name and empty choices become null.
    public var updatePayload: ScreenUpdatePayload {
        ScreenUpdatePayload(name: name?.trimmingCharacters(in: .whitespacesAndNewlines).blankToNil, locationId: locationId,
                            orientation: orientation.rawValue, defaultModule: defaultModule, groupId: groupId,
                            signageDefaultPlaylistId: signageDefaultPlaylistId, autoplay: autoplay)
    }
}

/// `screens.update(...)` body. Nulls are written explicitly (clearing a group or a playlist must reach the database).
public struct ScreenUpdatePayload: Encodable, Equatable, Sendable {
    public var name: String?
    public var locationId: UUID?
    public var orientation: String
    public var defaultModule: String
    public var groupId: UUID?
    public var signageDefaultPlaylistId: UUID?
    public var autoplay: Bool

    enum CodingKeys: String, CodingKey {
        case name, orientation, autoplay
        case locationId = "location_id", defaultModule = "default_module", groupId = "group_id"
        case signageDefaultPlaylistId = "signage_default_playlist_id"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(locationId?.uuidString.lowercased(), forKey: .locationId)
        try c.encode(orientation, forKey: .orientation)
        try c.encode(defaultModule, forKey: .defaultModule)
        try c.encode(groupId?.uuidString.lowercased(), forKey: .groupId)
        try c.encode(signageDefaultPlaylistId?.uuidString.lowercased(), forKey: .signageDefaultPlaylistId)
        try c.encode(autoplay, forKey: .autoplay)
    }
}

/// The 6-character code a TV shows when it is not paired ("ABC 123").
public enum PairingCode {
    /// Letters and digits only, upper case (the website sends `code.replace(/\s/g, '')`; the database upper-cases and trims).
    public static func normalize(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init)).uppercased()
    }
    public static func isComplete(_ text: String) -> Bool { normalize(text).count == 6 }
    /// "ABC123" -> "ABC 123" while typing.
    public static func display(_ text: String) -> String {
        let n = String(normalize(text).prefix(6))
        guard n.count > 3 else { return n }
        return n.prefix(3) + " " + n.dropFirst(3)
    }
}

public enum ScreenRules {
    /// Only owners and admins edit, pair and unpair screens (`claim_screen` and `release_screen` call `is_org_admin`).
    public static func canManage(_ role: Role) -> Bool { ContentPermissions.isAdmin(role) }

    /// "2 screens of 5 allowed on your plan".
    public static func countLine(screens: Int, limit: Int?) -> String {
        let base = "\(screens) screen\(screens == 1 ? "" : "s")"
        guard let limit else { return base }
        return "\(base) of \(limit) allowed on your plan"
    }

    /// True when pairing another TV would be refused by `claim_screen`.
    public static func atLimit(screens: Int, limit: Int?) -> Bool { limit.map { screens >= $0 } ?? false }

    public static let portraitNote = "Portrait screen: use portrait media (1080 x 1920). YouTube items do not rotate on portrait screens."
}

// MARK: - People

/// A row of `memberships`.
public struct Member: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var organizationId: UUID
    /// nil until the person signs in with this email ("Invited, not signed up yet").
    public var userId: UUID?
    public var email: String
    public var role: Role
    public var modules: [String]
    /// nil = all sites.
    public var siteIds: [UUID]?
    public var createdAt: Date?

    public init(id: UUID = UUID(), organizationId: UUID, userId: UUID? = nil, email: String, role: Role, modules: [String], siteIds: [UUID]? = nil, createdAt: Date? = nil) {
        self.id = id; self.organizationId = organizationId; self.userId = userId; self.email = email; self.role = role
        self.modules = modules; self.siteIds = siteIds; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, email, role, modules
        case organizationId = "organization_id", userId = "user_id", siteIds = "site_ids", createdAt = "created_at"
    }
}

/// The form for inviting someone or editing their access.
public struct AccessDraft: Equatable, Sendable {
    public var email: String
    public var role: Role
    public var modules: [String]
    /// nil = all sites; an empty array is invalid ("Choose at least one site, or pick all sites.").
    public var siteIds: [UUID]?

    public init(email: String = "", role: Role = .editor, modules: [String], siteIds: [UUID]? = nil) {
        self.email = email; self.role = role; self.modules = modules; self.siteIds = siteIds
    }

    /// A new person starts as an editor with every available module and all sites (`blankFor` on the website).
    public static func blank(modules: [String]) -> AccessDraft { AccessDraft(modules: modules) }

    public init(_ member: Member) { self.init(email: member.email, role: member.role, modules: member.modules, siteIds: member.siteIds) }

    public mutating func toggleModule(_ id: String) {
        if let i = modules.firstIndex(of: id) { modules.remove(at: i) } else { modules.append(id) }
    }

    public mutating func toggleSite(_ id: UUID) {
        var list = siteIds ?? []
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id) }
        siteIds = list
    }

    public mutating func setAllSites(_ all: Bool) { siteIds = all ? nil : [] }
}

public enum PeopleRules {
    /// "People" and "Settings" are for owners and admins (`adminOnly` on the website).
    public static func canManage(_ role: Role) -> Bool { ContentPermissions.isAdmin(role) }

    /// Owners and admins always have every module and every site.
    public static func hasEverything(_ role: Role) -> Bool { ContentPermissions.isAdmin(role) }

    public static func roleHelp(_ role: Role) -> String {
        switch role {
        case .owner: return "Everything, including people"
        case .admin: return "Manage people, sites, screens and content"
        case .editor: return "Edit content in their modules"
        case .operator: return "View only (for now)"
        }
    }

    public static func normalizedEmail(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Same checks as the website's forms. `isInvite` also requires an email address.
    public static func problem(_ draft: AccessDraft, isInvite: Bool) -> String? {
        if isInvite {
            let e = normalizedEmail(draft.email)
            let parts = e.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !e.contains(" ") else { return "Enter a valid email address." }
        }
        if let ids = draft.siteIds, ids.isEmpty { return "Choose at least one site, or pick all sites." }
        return nil
    }

    /// Row inserted by "Give access".
    public static func insertRow(organizationId: UUID, draft: AccessDraft) -> NewMembershipRow {
        NewMembershipRow(organizationId: organizationId, email: normalizedEmail(draft.email), role: draft.role, modules: draft.modules, siteIds: draft.siteIds)
    }

    /// One line under a person's email: "Editor · Kids, Slides · All sites · Active".
    public static func summary(_ m: Member, moduleNames: [String: String], sites: [Site]) -> String {
        let everything = hasEverything(m.role)
        let mods = everything ? "All modules"
            : (m.modules.filter { moduleNames[$0] != nil }.map { moduleNames[$0] ?? $0 }.joined(separator: ", ").blankToNil ?? "No modules")
        let scope: String
        if everything || m.siteIds == nil { scope = "All sites" }
        else { scope = (m.siteIds ?? []).map { id in sites.first { $0.id == id }?.name ?? "?" }.joined(separator: ", ") }
        return [m.role.displayName, mods, scope, m.userId != nil ? "Active" : "Invited, not signed up yet"].joined(separator: " · ")
    }

    /// You cannot remove yourself (the website hides Remove on your own row).
    public static func canRemove(_ m: Member, currentUserId: UUID?) -> Bool { m.userId == nil || m.userId != currentUserId }

    public static let inviteNote = "No email is sent. Ask them to open the dashboard and sign in (or create an account) with this same email address and they will see the church straight away."
}

/// Body of `memberships.insert`.
public struct NewMembershipRow: Encodable, Equatable, Sendable {
    public var organizationId: UUID
    public var email: String
    public var role: Role
    public var modules: [String]
    public var siteIds: [UUID]?

    enum CodingKeys: String, CodingKey { case email, role, modules, organizationId = "organization_id", siteIds = "site_ids" }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(organizationId.uuidString.lowercased(), forKey: .organizationId)
        try c.encode(email, forKey: .email)
        try c.encode(role, forKey: .role)
        try c.encode(modules, forKey: .modules)
        try c.encode(siteIds?.map { $0.uuidString.lowercased() }, forKey: .siteIds)   // explicit null = all sites
    }
}

/// Body of `memberships.update` (the website writes role, modules and site_ids).
public struct MembershipUpdatePayload: Encodable, Equatable, Sendable {
    public var role: Role
    public var modules: [String]
    public var siteIds: [UUID]?
    public init(_ draft: AccessDraft) { role = draft.role; modules = draft.modules; siteIds = draft.siteIds }
    enum CodingKeys: String, CodingKey { case role, modules, siteIds = "site_ids" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(modules, forKey: .modules)
        try c.encode(siteIds?.map { $0.uuidString.lowercased() }, forKey: .siteIds)
    }
}

/// A row of the `modules` registry. Hidden when `available` is false.
public struct ModuleDef: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var sort: Int
    public var available: Bool
    public init(id: String, name: String, sort: Int = 0, available: Bool = true) { self.id = id; self.name = name; self.sort = sort; self.available = available }
}

// MARK: - Plan (read only for church admins)

/// A row of `entitlements`.
public struct PlanRow: Codable, Hashable, Identifiable, Sendable {
    public var module: String
    public var status: String
    public var tvLimit: Int
    public var plan: String
    public var currentPeriodEnd: Date?
    public var graceEndsAt: Date?
    public var id: String { module }
    public init(module: String, status: String, tvLimit: Int, plan: String, currentPeriodEnd: Date? = nil, graceEndsAt: Date? = nil) {
        self.module = module; self.status = status; self.tvLimit = tvLimit; self.plan = plan; self.currentPeriodEnd = currentPeriodEnd; self.graceEndsAt = graceEndsAt
    }
    enum CodingKeys: String, CodingKey {
        case module, status, plan
        case tvLimit = "tv_limit", currentPeriodEnd = "current_period_end", graceEndsAt = "grace_ends_at"
    }

    /// Same rule as the database `entitlement_live` (and `entitled()` on the website): suspended churches have nothing live.
    public func isLive(churchSuspended: Bool = false, now: Date = Date()) -> Bool {
        if churchSuspended { return false }
        switch status {
        case "active": return true
        case "trialing": return currentPeriodEnd.map { $0 > now } ?? true
        case "past_due": return graceEndsAt.map { $0 > now } ?? false
        default: return false
        }
    }

    public var summary: String { "\(status) · \(plan) · up to \(tvLimit) TV\(tvLimit == 1 ? "" : "s")" }
}

// MARK: - Church settings and branding

/// The `organizations` fields the Settings page edits.
public struct OrganizationSettings: Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var slug: String
    public var branding: BrandingSettings
    public init(id: UUID, name: String, slug: String, branding: BrandingSettings = BrandingSettings()) { self.id = id; self.name = name; self.slug = slug; self.branding = branding }
}

/// Which look is being edited: the church default or one module's override.
public enum BrandScope: String, CaseIterable, Identifiable, Sendable {
    case church, kids, signage, slides
    public var id: String { rawValue }
    public var title: String { self == .church ? "Church (default)" : AppModule(rawValue: rawValue)?.displayName ?? rawValue }
    public var module: AppModule? { AppModule(rawValue: rawValue) }
}

/// One look: the church's default or one module's override. Backed by the raw JSON object, so keys this app does not know survive a save.
/// Unset fields inherit (church look, then built-in defaults).
public struct BrandLook: Hashable, Sendable {
    public var object: RawObject
    public init(object: RawObject = [:]) { self.object = object }

    public var logoURL: String? { get { string("logo_url") } set { set("logo_url", newValue) } }
    public var logoDarkURL: String? { get { string("logo_dark_url") } set { set("logo_dark_url", newValue) } }
    public var primaryColor: String? { get { string("primary_color") } set { set("primary_color", newValue) } }
    public var accentColor: String? { get { string("accent_color") } set { set("accent_color", newValue) } }

    public var splashEnabled: Bool? {
        get { object["splash"]?["enabled"]?.boolValue }
        set { setSplash("enabled", newValue.map(RawJSON.bool)) }
    }
    public var splashSeconds: Int? {
        get { object["splash"]?["seconds"]?.intValue }
        set { setSplash("seconds", newValue.map { RawJSON.number(Double($0)) }) }
    }

    private func string(_ key: String) -> String? {
        guard let s = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
    private mutating func set(_ key: String, _ value: String?) {
        if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { object[key] = .string(v) } else { object.removeValue(forKey: key) }
    }
    private mutating func setSplash(_ key: String, _ value: RawJSON?) {
        var splash = object["splash"]?.objectValue ?? [:]
        if let value { splash[key] = value } else { splash.removeValue(forKey: key) }
        if splash.isEmpty { object.removeValue(forKey: "splash") } else { object["splash"] = .object(splash) }
    }

    public var isEmpty: Bool { object.isEmpty }
}

/// `organizations.branding`: the church look at the top level, per-module looks under `modules`, plus the YouTube channel id.
public struct BrandingSettings: Hashable, Sendable {
    public static let defaultPrimary = "#1f3a5f"
    public static let defaultAccent = "#e8833a"
    public static let defaultSplashSeconds = 5
    public static let splashRange = 2...30

    public var object: RawObject
    public init(object: RawObject = [:]) { self.object = object }
    public init(json: RawJSON?) { self.init(object: json?.objectValue ?? [:]) }

    public var json: RawJSON { .object(object) }

    public func look(_ scope: BrandScope) -> BrandLook {
        scope == .church ? BrandLook(object: object.filter { $0.key != "modules" && $0.key != "youtube_channel_id" })
            : BrandLook(object: object["modules"]?[scope.rawValue]?.objectValue ?? [:])
    }

    public mutating func setLook(_ look: BrandLook, for scope: BrandScope) {
        if scope == .church {
            let keep = object.filter { $0.key == "modules" || $0.key == "youtube_channel_id" }
            object = look.object.merging(keep) { a, _ in a }
        } else {
            var modules = object["modules"]?.objectValue ?? [:]
            if look.isEmpty { modules.removeValue(forKey: scope.rawValue) } else { modules[scope.rawValue] = .object(look.object) }
            if modules.isEmpty { object.removeValue(forKey: "modules") } else { object["modules"] = .object(modules) }
        }
    }

    public mutating func update(_ scope: BrandScope, _ change: (inout BrandLook) -> Void) {
        var l = look(scope); change(&l); setLook(l, for: scope)
    }

    public var youtubeChannelId: String? {
        get { object["youtube_channel_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).blankToNil }
        set { if let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { object["youtube_channel_id"] = .string(v) } else { object.removeValue(forKey: "youtube_channel_id") } }
    }

    /// What a module actually uses: its own settings, else the church's, else the built-in defaults (`resolve` in BrandingEditor.tsx).
    public struct Effective: Equatable, Sendable {
        public var logoURL: String?
        public var logoDarkURL: String?
        public var primary: String
        public var accent: String
        public var splashEnabled: Bool
        public var splashSeconds: Int
    }

    public func effective(_ scope: BrandScope) -> Effective {
        let church = look(.church), own = look(scope)
        func hex(_ v: String?) -> String? { ColorTools.isHex(v) ? v?.lowercased() : nil }
        return Effective(
            logoURL: own.logoURL ?? church.logoURL, logoDarkURL: own.logoDarkURL ?? church.logoDarkURL,
            primary: hex(own.primaryColor) ?? hex(church.primaryColor) ?? Self.defaultPrimary,
            accent: hex(own.accentColor) ?? hex(church.accentColor) ?? Self.defaultAccent,
            splashEnabled: own.splashEnabled ?? church.splashEnabled ?? false,
            splashSeconds: own.splashSeconds ?? church.splashSeconds ?? Self.defaultSplashSeconds)
    }

    /// The website's save check for the YouTube channel id: `UC` followed by 22 letters, digits, `_` or `-`.
    public static func isValidYouTubeChannelId(_ id: String) -> Bool {
        let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count == 24, t.hasPrefix("UC") else { return false }
        return t.dropFirst(2).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// Validation message for "Save settings", or nil.
    public static func problem(name: String, youtubeChannelId: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the church a name." }
        let id = youtubeChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty && !isValidYouTubeChannelId(id) { return "That does not look like a YouTube channel ID. It starts with UC and is 24 characters long." }
        return nil
    }

    /// Clamp "seconds on screen" the way the website does (2...30).
    public static func clampSplashSeconds(_ n: Int) -> Int { min(Self.splashRange.upperBound, max(Self.splashRange.lowerBound, n)) }

    /// Storage path for an uploaded logo: `<org>/branding/<random>-<filename>`.
    public static func logoPath(organizationId: UUID, filename: String, uuid: UUID = UUID()) -> String {
        "\(organizationId.uuidString.lowercased())/branding/\(uuid.uuidString.lowercased())-\(MediaPath.sanitize(filename))"
    }
}

extension String {
    var blankToNil: String? { isEmpty ? nil : self }
}
