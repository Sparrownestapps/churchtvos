import Foundation

// Creating a room (a `locations` row) and, if needed, a site while pairing a TV. Mirrors the website's Sites & Locations page:
// `sites.insert({organization_id, name, timezone})` then `locations.insert({organization_id, site_id, name, modules})`.
// Row-level security ("admins manage sites/locations") limits both to owners and admins, the same people who may pair.

/// What the user typed into the "+ New room…" form.
public struct NewRoomDraft: Equatable, Sendable {
    public var name: String
    /// An existing site, or nil together with `newSiteName` when a new site is being created.
    public var siteId: UUID?
    public var creatingSite: Bool
    public var newSiteName: String
    public var newSiteTimeZone: String
    public var modules: Set<String>

    public init(name: String = "", siteId: UUID? = nil, creatingSite: Bool = false, newSiteName: String = "", newSiteTimeZone: String = TimeZone.current.identifier, modules: Set<String> = []) {
        self.name = name; self.siteId = siteId; self.creatingSite = creatingSite
        self.newSiteName = newSiteName; self.newSiteTimeZone = newSiteTimeZone; self.modules = modules
    }
}

public struct NewSiteRow: Encodable, Equatable, Sendable {
    public let organizationId: UUID; public let name: String; public let timezone: String
    enum CodingKeys: String, CodingKey { case name, timezone, organizationId = "organization_id" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(organizationId.uuidString.lowercased(), forKey: .organizationId)
        try c.encode(name, forKey: .name)
        try c.encode(timezone, forKey: .timezone)
    }
}

public struct NewLocationRow: Encodable, Equatable, Sendable {
    public let organizationId: UUID; public let siteId: UUID; public let name: String; public let modules: [String]
    enum CodingKeys: String, CodingKey { case name, modules, organizationId = "organization_id", siteId = "site_id" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(organizationId.uuidString.lowercased(), forKey: .organizationId)
        try c.encode(siteId.uuidString.lowercased(), forKey: .siteId)
        try c.encode(name, forKey: .name)
        try c.encode(modules, forKey: .modules)
    }
}

public enum RoomRules {
    /// Picker tags for the "+ New room…" and "+ New site…" choices (never real row ids).
    public static let newRoomTag = UUID(uuidString: "FFFFFFFF-0000-4000-8000-00000000A001")!
    public static let newSiteTag = UUID(uuidString: "FFFFFFFF-0000-4000-8000-00000000A002")!

    /// The form as it first opens: the church's modules ticked, the only site chosen (or a new site when the church has none).
    public static func initialDraft(churchModules: [AppModule], sites: [Site], device: String = TimeZone.current.identifier) -> NewRoomDraft {
        NewRoomDraft(siteId: sites.count == 1 ? sites.first?.id : nil, creatingSite: sites.isEmpty,
                     newSiteTimeZone: defaultTimeZone(sites: sites, device: device), modules: defaultModules(church: churchModules))
    }

    /// Only owners and admins (RLS `is_org_admin`), the same people who may pair.
    public static func canCreate(_ role: Role) -> Bool { ScreenRules.canPair(role) }

    public static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Case-insensitive, trimmed comparison (the database compares exactly; this is stricter on purpose).
    static func same(_ a: String, _ b: String) -> Bool { trimmed(a).caseInsensitiveCompare(trimmed(b)) == .orderedSame }

    /// The church's modules in stable order (kids, signage, slides), as `locations.modules` tags.
    public static func defaultModules(church: [AppModule]) -> Set<String> {
        Set(church.map(\.rawValue))
    }

    /// Time zone for a new site: the first existing site's, otherwise the device's.
    public static func defaultTimeZone(sites: [Site], device: String = TimeZone.current.identifier) -> String {
        sites.compactMap(\.timezone).first { TimeZone(identifier: $0) != nil } ?? device
    }

    public static func isValidTimeZone(_ id: String) -> Bool { TimeZone(identifier: trimmed(id)) != nil }

    /// The first thing wrong with the form, or nil. Names must be unique: rooms within their site, sites within the church.
    public static func problem(_ d: NewRoomDraft, role: Role, sites: [Site], locations: [Location], validModules: [String] = AppModule.allCases.map(\.rawValue)) -> String? {
        guard canCreate(role) else { return "Only church owners and admins can create rooms." }
        let name = trimmed(d.name)
        if name.isEmpty { return "Enter a name for the room." }
        if d.creatingSite {
            let site = trimmed(d.newSiteName)
            if site.isEmpty { return "Enter a name for the new site." }
            if sites.contains(where: { same($0.name, site) }) { return "A site named \"\(site)\" already exists. Choose it from the list instead." }
            if !isValidTimeZone(d.newSiteTimeZone) { return "Choose a time zone for the new site." }
        } else {
            guard let siteId = d.siteId, sites.contains(where: { $0.id == siteId }) else { return "Choose the site this room belongs to." }
            if locations.contains(where: { $0.siteId == siteId && same($0.name, name) }) { return "A room named \"\(name)\" already exists in this site." }
        }
        let tags = d.modules.filter(validModules.contains)
        if tags.isEmpty { return "Choose at least one application for this room." }
        return nil
    }

    /// Module tags in a stable order, unknown values dropped.
    public static func orderedModules(_ tags: Set<String>) -> [String] {
        AppModule.allCases.map(\.rawValue).filter(tags.contains)
    }

    public static func siteRow(organizationId: UUID, name: String, timezone: String) -> NewSiteRow {
        NewSiteRow(organizationId: organizationId, name: trimmed(name), timezone: trimmed(timezone))
    }

    public static func locationRow(organizationId: UUID, siteId: UUID, name: String, modules: Set<String>) -> NewLocationRow {
        NewLocationRow(organizationId: organizationId, siteId: siteId, name: trimmed(name), modules: orderedModules(modules))
    }

    public static func friendlyCreateError(_ error: Error, what: String) -> String {
        let m = ContentErrors.friendly(Formatting.message(for: error))
        let l = m.lowercased()
        if l.contains("duplicate key") || l.contains("already exists") { return "\(what) with that name already exists." }
        return m
    }
}

/// How far a "pair into a new room" attempt got. Created rows are kept so a retry does not duplicate them.
public struct RoomPairingResult: Sendable {
    public var site: Site?          // set when this attempt created a new site
    public var location: Location?  // set when the room exists (created now)
    public var paired = false
    public var message: String?     // set when something failed

    public init() {}
}

public enum RoomPairing {
    /// Creates the site (if the draft asks for one), then the room, then claims the TV, in that order. Never throws: the result
    /// says what exists and what failed. A failed claim keeps the room (`location` is set, `paired` is false).
    public static func run(ops: OperationsService, organizationId: UUID, code: String, tvName: String?, draft: NewRoomDraft, existingSite: Site?) async -> RoomPairingResult {
        var result = RoomPairingResult()
        var siteId = draft.siteId
        if draft.creatingSite {
            do {
                let site = try await ops.createSite(organizationId: organizationId, name: draft.newSiteName, timezone: draft.newSiteTimeZone)
                result.site = site; siteId = site.id
            } catch {
                result.message = RoomRules.friendlyCreateError(error, what: "A site")
                return result
            }
        }
        guard let siteId else { result.message = "Choose the site this room belongs to."; return result }
        do {
            result.location = try await ops.createLocation(organizationId: organizationId, siteId: siteId, name: draft.name, modules: RoomRules.orderedModules(draft.modules))
        } catch {
            let created = result.site.map { " The site \"\($0.name)\" was created." } ?? ""
            result.message = RoomRules.friendlyCreateError(error, what: "A room") + created + " Nothing was paired."
            return result
        }
        guard let location = result.location else { return result }
        do {
            try await ops.claimScreen(code: code, locationId: location.id, name: tvName)
            result.paired = true
        } catch {
            result.message = "The room \"\(location.name)\" was created, but the TV could not be paired: \(ScreenRules.pairingMessage(for: error)) The room is selected, so you can try again."
        }
        return result
    }
}
