import Foundation

/// Demo mode: a believable sample church that behaves like the real thing. Commands move the mock status,
/// so every screen of the app can be exercised without an account (also what App Store reviewers use).
public actor MockService: ChurchService {
    public nonisolated var isDemo: Bool { true }

    public static let churchId = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000001")!
    /// Demo church has the experimental NDI flag on with the `-ndi` launch argument (or the `demoNdi` default); off otherwise, like a real church.
    public static var demoNdiEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ndi") || UserDefaults.standard.bool(forKey: "demoNdi")
    }
    public static let demoUser = SessionUser(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000AA")!, email: "demo@churchtvos.com")

    // MARK: Sample content

    public static let sundayDeck = Deck(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000D1")!, name: "Sunday 10:30 Service")
    public static let christmasDeck = Deck(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000D2")!, name: "Christmas Eve")
    public static let braveList = PlaylistRef(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000E1")!, name: "Week 3 · Brave Like David")
    public static let gardenList = PlaylistRef(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000E2")!, name: "Week 4 · The Good Gardener")

    static let sundayOutline = [
        "Countdown 5:00", "Welcome", "Great Are You Lord (title)", "Great Are You Lord · Verse 1", "Great Are You Lord · Chorus",
        "Great Are You Lord · Verse 2", "Great Are You Lord · Chorus", "Great Are You Lord · Bridge", "Announcements",
        "Sermon title: Anchored", "Scripture · Hebrews 6:19", "Offering", "Closing song (title)", "Closing song · Verse 1",
        "Closing song · Chorus", "Thank you / See you next week",
    ]
    static let kidsOutline = [
        "Welcome video", "Countdown 5:00", "Worship · This Little Light", "Story · David and Goliath",
        "Memory verse · Joshua 1:9", "Game time", "Prayer", "Goodbye video",
    ]
    static let lobbyOutline = ["Welcome", "Kids check-in", "Coffee bar", "Next steps", "Prayer team", "Giving"]

    struct MockScreen {
        var info: ScreenInfo
        var online: Bool
        var statusModule: String?
        var state: PlaybackState
        var title: String?
        var outline: [String]
        var index: Int
        var refKind: String?
        var refId: UUID?
        var resumeState: PlaybackState?       // what to return to after a message
        var messageUntil: Date?
    }

    private var screens: [UUID: MockScreen]
    private var order: [UUID]
    private var commandTimes: [Date] = []
    private var offlineAlerts = true
    /// Editable demo content (playlists, decks, themes, songs, media). See MockService+Content.swift.
    var store = MockContentStore.make()
    private let siteTZ = TimeZone.current.identifier

    public init() {
        let site = Site(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000B1")!, name: "Downtown Campus")
        let aud = Self.id(1), kids = Self.id(2), lobby = Self.id(3), youth = Self.id(4)
        let now = Date()

        // The demo screens sit in the demo locations (MockContent) so the calendar can filter by room.
        let locationIds: [String: UUID] = ["Auditorium": MockContentStore.uuid(5, 1), "Kids Wing": MockContentStore.uuid(5, 2), "Lobby": MockContentStore.uuid(5, 3), "Youth Loft": MockContentStore.uuid(5, 4)]
        func make(_ id: UUID, _ name: String, _ loc: String, module: String, appVersion: String, lastSeen: Date, online: Bool,
                  state: PlaybackState, title: String?, outline: [String], index: Int, kind: String?, ref: UUID?) -> MockScreen {
            let screen = Screen(id: id, organizationId: MockService.churchId, locationId: locationIds[loc] ?? UUID(), name: name, orientation: "landscape",
                                defaultModule: module, model: "Fire TV Stick 4K", appVersion: appVersion, lastSeenAt: lastSeen)
            let info = ScreenInfo(screen: screen, locationName: loc, siteName: site.name, timeZoneId: TimeZone.current.identifier, status: nil)
            return MockScreen(info: info, online: online, statusModule: module, state: state, title: title, outline: outline, index: index, refKind: kind, refId: ref)
        }

        let list: [MockScreen] = [
            make(aud, "Main Auditorium", "Auditorium", module: "slides", appVersion: "1.5.1", lastSeen: now, online: true,
                 state: .playing, title: Self.sundayDeck.name, outline: Self.sundayOutline, index: 3, kind: "deck", ref: Self.sundayDeck.id),
            make(kids, "Kids Room 1", "Kids Wing", module: "kids", appVersion: "1.5.1", lastSeen: now, online: true,
                 state: .blank, title: Self.braveList.name, outline: Self.kidsOutline, index: 1, kind: "playlist", ref: Self.braveList.id),
            make(lobby, "Lobby TV", "Lobby", module: "signage", appVersion: "1.4.1", lastSeen: now, online: true,
                 state: .idle, title: nil, outline: [], index: 0, kind: nil, ref: nil),
            make(youth, "Youth Room", "Youth Loft", module: "slides", appVersion: "1.5.0", lastSeen: now.addingTimeInterval(-26 * 60), online: false,
                 state: .playing, title: "Youth Night", outline: Self.sundayOutline, index: 2, kind: "deck", ref: Self.sundayDeck.id),
        ]
        screens = Dictionary(uniqueKeysWithValues: list.map { ($0.info.id, $0) })
        order = list.map { $0.info.id }
    }

    static func id(_ n: Int) -> UUID { UUID(uuidString: "D0D0D0D0-0000-4000-8000-00000000010\(n)")! }

    // MARK: Session

    public func restoreSession() async -> SessionUser? { nil }
    public func signIn(email: String, password: String) async throws -> SessionUser { Self.demoUser }
    public func signOut() async {}

    public func loadChurches() async throws -> [ChurchAccess] {
        [ChurchAccess(organization: Organization(id: Self.churchId, name: "Grace Community Church (Demo)", slug: "grace-demo", ndiEnabled: Self.demoNdiEnabled),
                      role: .admin, modules: AppModule.allCases)]
    }

    // MARK: Screens

    /// Applies time-based changes (messages ending) and returns the current rows. Online screens "check in" on every call.
    private func refresh() {
        let now = Date()
        for id in order {
            guard var s = screens[id] else { continue }
            if s.online { s.info.screen.lastSeenAt = now }
            if let until = s.messageUntil, until <= now { s.state = s.resumeState ?? .playing; s.messageUntil = nil; s.resumeState = nil }
            s.info.status = status(for: s, now: now)
            screens[id] = s
        }
    }

    private func status(for s: MockScreen, now: Date) -> ScreenStatus? {
        // The old-version TV (1.4.1) predates status reporting: it never writes a row.
        if s.info.screen.appVersion.map({ !ScreenHealth.supportsRemote(appVersion: $0) }) == true { return nil }
        let label = s.state == .idle || s.outline.isEmpty ? nil : s.outline[min(s.index, s.outline.count - 1)]
        return ScreenStatus(screenId: s.info.id, organizationId: Self.churchId, module: s.statusModule, state: s.state, title: s.title,
                            itemLabel: label, slideIndex: s.state == .idle || s.outline.isEmpty ? nil : s.index,
                            slideCount: s.state == .idle || s.outline.isEmpty ? nil : s.outline.count,
                            updatedAt: s.online ? now : now.addingTimeInterval(-26 * 60),
                            outline: s.outline.isEmpty || s.state == .idle ? nil : s.outline, refKind: s.refKind, refId: s.refId)
    }

    public func listScreens(organizationId: UUID) async throws -> [ScreenInfo] {
        try await Task.sleep(nanoseconds: 150_000_000)
        refresh()
        return order.compactMap { screens[$0]?.info }
    }

    public func fetchStatuses(organizationId: UUID) async throws -> [UUID: ScreenStatus] {
        refresh()
        return Dictionary(uniqueKeysWithValues: order.compactMap { id in screens[id]?.info.status.map { (id, $0) } })
    }

    // MARK: Commands

    public func send(_ command: RemoteCommand, to screenId: UUID) async throws {
        if let problem = command.validationError { throw ChurchError(problem) }
        guard var s = screens[screenId] else { throw ChurchError("You do not have access to control that screen") }
        // Same rule as the database: more than 20 commands in 10 seconds is refused.
        let now = Date()
        commandTimes = commandTimes.filter { now.timeIntervalSince($0) < 10 }
        if commandTimes.count >= 20 { throw ChurchError("Too many commands, wait a moment") }
        commandTimes.append(now)

        let last = max(0, s.outline.count - 1)
        switch command {
        case .next:
            if s.state != .idle { s.index = min(last, s.index + 1); if s.state == .blank { s.state = .playing } }
        case .previous:
            if s.state != .idle { s.index = max(0, s.index - 1); if s.state == .blank { s.state = .playing } }
        case .jump(let i):
            if s.state != .idle { s.index = min(last, max(0, i)); if s.state == .blank { s.state = .playing } }
        case .blank(let on):
            if s.state == .playing || s.state == .blank {
                let wantBlank = on ?? (s.state != .blank)
                s.state = wantBlank ? .blank : .playing
            }
        case .stop:
            s.state = .idle; s.title = nil; s.outline = []; s.index = 0; s.refKind = nil; s.refId = nil
        case .start(let kind, let id, _):
            s.state = .playing; s.index = 0; s.refKind = kind.rawValue; s.refId = id
            if kind == .deck {
                s.statusModule = "slides"
                s.title = id == Self.christmasDeck.id ? Self.christmasDeck.name : Self.sundayDeck.name
                s.outline = Self.sundayOutline
            } else {
                s.statusModule = "kids"
                s.title = id == Self.gardenList.id ? Self.gardenList.name : Self.braveList.name
                s.outline = Self.kidsOutline
            }
        case .message(_, let seconds, _):
            s.resumeState = s.messageUntil == nil ? s.state : s.resumeState
            s.state = .message; s.messageUntil = now.addingTimeInterval(TimeInterval(seconds))
        case .clearMessage:
            if s.state == .message { s.state = s.resumeState ?? .playing; s.messageUntil = nil; s.resumeState = nil }
        }
        s.info.status = status(for: s, now: now)
        screens[screenId] = s
    }

    // MARK: Content

    public func playNowItems(organizationId: UUID, modules: [AppModule]) async throws -> [PlayNowItem] {
        var items: [PlayNowItem] = []
        if modules.contains(.slides) {
            items += store.decks.sorted { $0.name < $1.name }.map { PlayNowItem(kind: .deck, refId: $0.id, name: $0.name) }
        }
        if modules.contains(.kids) {
            items += store.kids.sorted { $0.name < $1.name }.map { PlayNowItem(kind: .playlist, refId: $0.id, name: $0.name) }
        }
        return items
    }

    public func schedule(organizationId: UUID, screens infos: [ScreenInfo], modules: [AppModule], now: Date) async throws -> [ScheduleEntry] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day }
        let a = Self.id(1), k = Self.id(2), l = Self.id(3), y = Self.id(4)
        let entries = [
            ScheduleEntry(id: "m1", screenId: a, module: .slides, title: "Band rehearsal lyrics", starts: at(8, 30), ends: at(9, 45), source: .oneOff),
            ScheduleEntry(id: "m2", screenId: a, module: .slides, title: Self.sundayDeck.name, starts: at(10, 15), ends: at(12), source: .repeating),
            ScheduleEntry(id: "m3", screenId: k, module: .kids, title: Self.braveList.name, starts: at(10, 15), ends: at(12), source: .repeating),
            ScheduleEntry(id: "m4", screenId: l, module: .signage, title: "Runs Signage", starts: at(0), ends: at(23, 59), source: .moduleRule),
            ScheduleEntry(id: "m5", screenId: y, module: .slides, title: "Youth Night", starts: at(18, 30), ends: at(20, 30), source: .oneOff),
        ]
        return entries.filter { e in infos.contains { $0.id == e.screenId } && modules.contains(e.module) }
    }

    // MARK: Media

    public func mediaFolders(organizationId: UUID, module: AppModule) async throws -> [MediaFolder] {
        store.folders.filter { $0.module == module.rawValue }.sorted { $0.name < $1.name }
    }

    public func uploadMedia(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await uploadMediaItem(request, progress: progress)
    }

    // MARK: Push

    public func registerPushToken(_ token: String, environment: PushEnvironment) async throws {}
    public func removePushToken(_ token: String) async throws {}
    public func offlineAlertsEnabled(organizationId: UUID) async throws -> Bool { offlineAlerts }
    public func setOfflineAlerts(organizationId: UUID, enabled: Bool) async throws { offlineAlerts = enabled }
}
