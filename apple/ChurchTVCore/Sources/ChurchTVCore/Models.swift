import Foundation

// MARK: - Decoding

/// Decoder for the JSON shapes PostgREST returns (snake_case keys, ISO-8601 timestamps with or without fractions,
/// plain `date` / `time` values as strings).
public enum ChurchJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = parseTimestamp(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised date \(s)")
        }
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatTimestamp(date))
        }
        return e
    }

    public static func parseTimestamp(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // Postgres sometimes writes "2026-10-22 14:03:11.123456+00"
        let pg = DateFormatter()
        pg.locale = Locale(identifier: "en_US_POSIX")
        for f in ["yyyy-MM-dd HH:mm:ss.SSSSSSxxx", "yyyy-MM-dd HH:mm:ssxxx", "yyyy-MM-dd HH:mm:ss.SSSSSSx", "yyyy-MM-dd HH:mm:ssx"] {
            pg.dateFormat = f
            if let d = pg.date(from: s) { return d }
        }
        return nil
    }

    public static func formatTimestamp(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}

// MARK: - Organizations and roles

public enum Role: String, Codable, Sendable, CaseIterable {
    case owner, admin, editor, `operator`

    public var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .editor: return "Editor"
        case .operator: return "Operator"
        }
    }
    /// Operators and above may send commands to a screen (database function can_control_screen).
    public var canControl: Bool { true }
    /// Only editors and above may add media or edit content.
    public var canEditContent: Bool { self != .operator }
}

public struct Organization: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var slug: String?
    public init(id: UUID, name: String, slug: String? = nil) {
        self.id = id; self.name = name; self.slug = slug
    }
}

/// A user's membership in a church. `organizations` is the embedded parent row from
/// `memberships?select=...,organizations(id,name,slug)`.
public struct Membership: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let organizationId: UUID
    public var role: Role
    public var modules: [String]
    public var siteIds: [UUID]?
    public var organizations: Organization?

    public init(id: UUID, organizationId: UUID, role: Role, modules: [String], siteIds: [UUID]? = nil, organizations: Organization? = nil) {
        self.id = id; self.organizationId = organizationId; self.role = role
        self.modules = modules; self.siteIds = siteIds; self.organizations = organizations
    }
}

/// One church the signed-in user can work in, with their role and the modules they may use.
public struct ChurchAccess: Hashable, Identifiable, Sendable {
    public var organization: Organization
    public var role: Role
    /// Modules the member has access to AND the church has an active/trialing entitlement for.
    public var modules: [AppModule]
    public var id: UUID { organization.id }
    public init(organization: Organization, role: Role, modules: [AppModule]) {
        self.organization = organization; self.role = role; self.modules = modules
    }
}

public enum AppModule: String, Codable, Sendable, CaseIterable, Identifiable {
    case kids, signage, slides
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .kids: return "Kids"
        case .signage: return "Signage"
        case .slides: return "Slides"
        }
    }
    public var symbol: String {
        switch self {
        case .kids: return "figure.and.child.holdinghands"
        case .signage: return "rectangle.on.rectangle"
        case .slides: return "play.rectangle.on.rectangle"
        }
    }
}

public struct Entitlement: Codable, Hashable, Sendable {
    public let module: String
    public let status: String
    /// Billing states in which the module still works (past_due has a grace period; we do not second-guess it).
    public var isUsable: Bool { status == "active" || status == "trialing" || status == "past_due" }
}

// MARK: - Screens

public struct Screen: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var organizationId: UUID?
    public var locationId: UUID?
    public var name: String?
    public var orientation: String?
    public var defaultModule: String?
    public var groupId: UUID?
    public var model: String?
    public var appVersion: String?
    public var lastSeenAt: Date?

    public init(id: UUID, organizationId: UUID? = nil, locationId: UUID? = nil, name: String? = nil, orientation: String? = nil,
                defaultModule: String? = nil, groupId: UUID? = nil, model: String? = nil, appVersion: String? = nil, lastSeenAt: Date? = nil) {
        self.id = id; self.organizationId = organizationId; self.locationId = locationId; self.name = name
        self.orientation = orientation; self.defaultModule = defaultModule; self.groupId = groupId; self.model = model
        self.appVersion = appVersion; self.lastSeenAt = lastSeenAt
    }

    public var displayName: String { (name?.isEmpty == false ? name : nil) ?? "Unnamed screen" }
}

public struct Location: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var siteId: UUID?
    public init(id: UUID, name: String, siteId: UUID? = nil) { self.id = id; self.name = name; self.siteId = siteId }
}

public struct Site: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var timezone: String?
    public init(id: UUID, name: String, timezone: String? = nil) { self.id = id; self.name = name; self.timezone = timezone }
}

public enum PlaybackState: String, Codable, Sendable {
    case idle, playing, blank, message
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlaybackState(rawValue: raw) ?? .unknown
    }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .playing: return "Playing"
        case .blank: return "Blank"
        case .message: return "Message"
        case .unknown: return "Unknown"
        }
    }
}

/// Row of `screen_status`, written by the TV. `slideIndex` is 0-based (the TV reports its internal index);
/// `outline[i]` is the label of slide i.
public struct ScreenStatus: Codable, Hashable, Sendable {
    public let screenId: UUID
    public var organizationId: UUID?
    public var module: String?
    public var state: PlaybackState
    public var title: String?
    public var itemLabel: String?
    public var slideIndex: Int?
    public var slideCount: Int?
    public var updatedAt: Date?
    public var outline: [String]?
    public var refKind: String?
    public var refId: UUID?

    public init(screenId: UUID, organizationId: UUID? = nil, module: String? = nil, state: PlaybackState = .idle, title: String? = nil,
                itemLabel: String? = nil, slideIndex: Int? = nil, slideCount: Int? = nil, updatedAt: Date? = nil,
                outline: [String]? = nil, refKind: String? = nil, refId: UUID? = nil) {
        self.screenId = screenId; self.organizationId = organizationId; self.module = module; self.state = state
        self.title = title; self.itemLabel = itemLabel; self.slideIndex = slideIndex; self.slideCount = slideCount
        self.updatedAt = updatedAt; self.outline = outline; self.refKind = refKind; self.refId = refId
    }

    /// 0-based current slide clamped into range, or nil when nothing is playing.
    public var currentIndex: Int? {
        guard let i = slideIndex, let n = slideCount, n > 0 else { return nil }
        return min(max(i, 0), n - 1)
    }

    /// "Slide 3 of 12", or nil when there is nothing to count.
    public var slideText: String? {
        guard let i = currentIndex, let n = slideCount else { return nil }
        return "Slide \(i + 1) of \(n)"
    }

    /// 0...1 progress through the deck.
    public var progress: Double {
        guard let i = currentIndex, let n = slideCount, n > 0 else { return 0 }
        return Double(i + 1) / Double(n)
    }
}

/// A screen with everything the UI needs to draw one card.
public struct ScreenInfo: Identifiable, Hashable, Sendable {
    public var screen: Screen
    public var locationName: String?
    public var siteName: String?
    public var timeZoneId: String?
    public var status: ScreenStatus?
    public var id: UUID { screen.id }

    public init(screen: Screen, locationName: String? = nil, siteName: String? = nil, timeZoneId: String? = nil, status: ScreenStatus? = nil) {
        self.screen = screen; self.locationName = locationName; self.siteName = siteName; self.timeZoneId = timeZoneId; self.status = status
    }

    public var timeZone: TimeZone { timeZoneId.flatMap(TimeZone.init(identifier:)) ?? .current }

    public func isOnline(now: Date = Date()) -> Bool { ScreenHealth.isOnline(lastSeen: screen.lastSeenAt, now: now) }
    public func isStatusStale(now: Date = Date()) -> Bool { ScreenHealth.isStatusStale(updatedAt: status?.updatedAt, now: now) }
    public var supportsRemote: Bool { ScreenHealth.supportsRemote(appVersion: screen.appVersion) }

    /// "Main Auditorium, Downtown" style location line.
    public var locationLine: String {
        [locationName, siteName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The state the card shows: Offline beats everything else.
    public func displayState(now: Date = Date()) -> ScreenDisplayState {
        if !isOnline(now: now) { return .offline }
        guard let st = status else { return .idle }
        if isStatusStale(now: now) { return .stale }
        switch st.state {
        case .playing: return .playing
        case .blank: return .blank
        case .message: return .message
        case .idle, .unknown: return .idle
        }
    }
}

public enum ScreenDisplayState: String, Sendable {
    case offline, stale, idle, playing, blank, message
    public var label: String {
        switch self {
        case .offline: return "Offline"
        case .stale: return "Not updating"
        case .idle: return "Idle"
        case .playing: return "Playing"
        case .blank: return "Blank"
        case .message: return "Message"
        }
    }
}

// MARK: - Content to start

public struct Deck: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}

/// Kids playlists (`playlists`) and Signage playlists share this shape.
public struct PlaylistRef: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}

public struct Song: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public init(id: UUID, title: String) { self.id = id; self.title = title }
}

/// What can be started on a screen with "Play now".
public struct PlayNowItem: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case deck, playlist }
    public let kind: Kind
    public let refId: UUID
    public let name: String
    public var id: String { "\(kind.rawValue)-\(refId.uuidString)" }
    public init(kind: Kind, refId: UUID, name: String) { self.kind = kind; self.refId = refId; self.name = name }
    /// Decks need the Slides module, playlists the Kids module.
    public var module: AppModule { kind == .deck ? .slides : .kids }
}

// MARK: - Media

public struct MediaFolder: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var module: String
    public var parentId: UUID?
    public var name: String
    public init(id: UUID, module: String, parentId: UUID? = nil, name: String) {
        self.id = id; self.module = module; self.parentId = parentId; self.name = name
    }
}

public enum MediaKind: String, Codable, Sendable { case image, video }

/// Row sent to `media` after the file is in storage. `module` and `folder` are required by the database
/// (folder may be nil = library root).
public struct NewMediaRow: Encodable, Sendable, Equatable {
    public var organizationId: UUID
    public var module: String
    public var title: String
    public var kind: String
    public var storagePath: String
    public var url: String
    public var sizeBytes: Int64
    public var folderId: UUID?

    public init(organizationId: UUID, module: String, title: String, kind: MediaKind, storagePath: String, url: String, sizeBytes: Int64, folderId: UUID?) {
        self.organizationId = organizationId; self.module = module; self.title = title; self.kind = kind.rawValue
        self.storagePath = storagePath; self.url = url; self.sizeBytes = sizeBytes; self.folderId = folderId
    }

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id", module, title, kind, storagePath = "storage_path", url
        case sizeBytes = "size_bytes", folderId = "folder_id"
    }

    // Encode folder_id explicitly as null when missing so the intent is visible in the payload.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(organizationId, forKey: .organizationId)
        try c.encode(module, forKey: .module)
        try c.encode(title, forKey: .title)
        try c.encode(kind, forKey: .kind)
        try c.encode(storagePath, forKey: .storagePath)
        try c.encode(url, forKey: .url)
        try c.encode(sizeBytes, forKey: .sizeBytes)
        try c.encode(folderId, forKey: .folderId)
    }
}

/// Storage path rule: `<organization_id>/<random-uuid>-<filename>` (the database requires the org prefix).
public enum MediaPath {
    public static func make(organizationId: UUID, filename: String, uuid: UUID = UUID()) -> String {
        "\(organizationId.uuidString.lowercased())/\(uuid.uuidString.lowercased())-\(sanitize(filename))"
    }

    /// Keep names URL-safe: letters, digits, dot, dash, underscore.
    public static func sanitize(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let cleaned = String(name.map { allowed.contains($0) ? $0 : "_" })
        return cleaned.isEmpty ? "file" : cleaned
    }
}
