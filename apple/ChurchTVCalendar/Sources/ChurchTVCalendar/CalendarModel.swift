import Foundation
import Observation
import ChurchTVCore

/// What the host (the app) is asked to do when the person taps a block or drags out a new one. The package never opens editors itself.
public struct CalendarCallbacks {
    /// A block was tapped (or "Open" in the error alert / VoiceOver action).
    public var onSelect: (CalendarEvent) -> Void
    /// A range was dragged out (or an empty slot tapped). Only called when `CalendarModel.canCreate`.
    public var onCreate: (CalendarCreateRequest) -> Void
    public init(onSelect: @escaping (CalendarEvent) -> Void = { _ in }, onCreate: @escaping (CalendarCreateRequest) -> Void = { _ in }) {
        self.onSelect = onSelect; self.onCreate = onCreate
    }
}

public struct CalendarCreateRequest: Equatable, Sendable, Identifiable {
    public var id: String { "\(day)@\(startMinute)-\(endMinute)" }
    public var day: CalendarDay
    public var startMinute: Int
    public var endMinute: Int
    public var lane: ResolvedLane
    public var timeZone: TimeZone { lane.timeZone }
    /// Locations the lane covers (the room(s) the new item should go to), in the church's order.
    public var locationIds: [UUID]
    public var start: WallTime { WallTime(day: day, minutes: startMinute) }
    public var end: WallTime { WallTime(day: day, minutes: endMinute) }
}

/// A block placed in a day column.
struct PlacedSegment: Identifiable {
    var segment: CalendarSegment
    var event: CalendarEvent
    var placement: CalendarGeometry.Placement
    var id: String { "\(segment.eventId)@\(segment.day)" }
}

public struct PendingCalendarEdit: Identifiable {
    public let id = UUID()
    public let event: CalendarEvent
    public let title: String
    public let message: String
    public let choices: [CalendarChoice]
}

@MainActor
@Observable
public final class CalendarModel {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case day, threeDay, week
        public var id: String { rawValue }
        public var title: String { switch self { case .day: return "Day"; case .threeDay: return "3 days"; case .week: return "Week" } }
        public var dayCount: Int { switch self { case .day: return 1; case .threeDay: return 3; case .week: return 7 } }
    }

    @ObservationIgnored public let service: any ChurchService
    public let church: ChurchAccess
    public var mode: Mode { didSet { if mode != oldValue { visibleChanged() } } }
    public private(set) var anchor: CalendarDay
    public var lane: CalendarLane = .all { didSet { if lane != oldValue { visibleChanged() } } }

    public private(set) var source: CalendarSource?
    public private(set) var isLoading = false
    public private(set) var isBusy = false
    public private(set) var loadError: String?
    public private(set) var warnings: [String] = []
    public var actionError: String?
    public var pendingEdit: PendingCalendarEdit?
    var placed: [CalendarDay: [PlacedSegment]] = [:]
    public private(set) var events: [CalendarEvent] = []
    public private(set) var bands: [CalendarBand] = []

    private var data = CalendarData()
    private var loadedRange: (from: Date, to: Date)?
    private var loadedKey = ""
    private var anchorWasSet: Bool
    private var loadTask: Task<Void, Never>?

    public init(service: any ChurchService, church: ChurchAccess, mode: Mode = .week, anchor: CalendarDay? = nil, lane: CalendarLane? = nil) {
        self.service = service; self.church = church; self.mode = mode
        self.anchor = anchor ?? SiteClock.day(of: Date(), in: .current)
        self.anchorWasSet = anchor != nil
        self.lane = lane ?? .all
        self.laneWasSet = lane != nil
    }
    private var laneWasSet: Bool

    // MARK: Derived

    public var permissions: CalendarPermissions { CalendarPermissions(church) }
    public var directory: CalendarDirectory { source?.directory ?? CalendarDirectory() }
    public var resolvedLane: ResolvedLane { directory.resolve(lane) }
    public var timeZone: TimeZone { resolvedLane.timeZone }
    public var canCreate: Bool { permissions.canCreate(locations: directory.locations) && !resolvedLane.locationIds.isEmpty }
    /// Operators and viewers see the calendar read-only.
    public var isReadOnly: Bool { !ContentPermissions.canEditRole(church.role) }
    public var modules: [AppModule] { church.modules }

    public var visibleDays: [CalendarDay] {
        let first = mode == .week ? anchor.mondayOfWeek : anchor
        return (0..<mode.dayCount).map { first.adding(days: $0) }
    }
    public var today: CalendarDay { SiteClock.day(of: Date(), in: timeZone) }

    /// "Oct 19 - 25, 2026"
    public var title: String {
        let days = visibleDays
        let tz = TimeZone(secondsFromGMT: 0)!
        func fmt(_ t: String, _ d: CalendarDay) -> String {
            let f = DateFormatter(); f.timeZone = tz; f.setLocalizedDateFormatFromTemplate(t); return f.string(from: d.noonUTC)
        }
        guard let a = days.first, let b = days.last, a != b else { return days.first.map { fmt("EEEMMMd", $0) } ?? "" }
        if a.month == b.month && a.year == b.year { return "\(fmt("MMMd", a)) - \(b.day), \(b.year)" }
        return "\(fmt("MMMd", a)) - \(fmt("MMMd", b)), \(b.year)"
    }

    public var timeZoneNote: String {
        let tz = timeZone
        let abbr = tz.abbreviation(for: Date()) ?? tz.identifier
        var s = "Times are in \(tz.identifier.replacingOccurrences(of: "_", with: " ")) (\(abbr))"
        if SiteClock.differsFromDevice(tz) { s += ", not your device's time zone" }
        if resolvedLane.mixedTimeZones { s += ". This view spans several time zones; times are shown in the first" }
        return s
    }
    public var timeZoneDiffers: Bool { SiteClock.differsFromDevice(timeZone) || resolvedLane.mixedTimeZones }

    /// Lane choices for the picker.
    public struct LaneOption: Identifiable, Hashable { public let lane: CalendarLane; public let title: String; public let group: String; public var id: CalendarLane { lane } }
    public var laneOptions: [LaneOption] {
        let d = directory
        var out = [LaneOption(lane: .all, title: "Everything", group: "")]
        for l in d.visibleLocations(siteIds: church.siteIds) { out.append(LaneOption(lane: .location(l.id), title: l.name, group: "Locations")) }
        for s in d.screens { out.append(LaneOption(lane: .screen(s.id), title: "\(s.screen.displayName)\(s.locationName.map { " · \($0)" } ?? "")", group: "Screens")) }
        for g in d.groups { out.append(LaneOption(lane: .group(g.id), title: g.name, group: "Screen groups")) }
        return out
    }

    // MARK: Navigation

    public func goToday() { anchor = today; visibleChanged() }
    public func goPrevious() { anchor = anchor.adding(days: -step); visibleChanged() }
    public func goNext() { anchor = anchor.adding(days: step); visibleChanged() }
    public func go(to day: CalendarDay) { anchor = day; visibleChanged() }
    private var step: Int { mode == .week ? 7 : mode.dayCount }

    // MARK: Loading

    /// First load: rooms, screens and names, then the visible range. Safe to call again (pull to refresh / after the host saved something).
    public func reload(force: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            if source == nil || force {
                let s = try await CalendarLoader.loadSource(service: service, organizationId: church.id, modules: church.modules)
                source = s
                data.names = s.names
                data.moduleRules = s.moduleRules
                // Like the website: start on the first screen (its room, its module switches); "Everything" stays in the filter.
                if !laneWasSet {
                    laneWasSet = true
                    if let sc = s.directory.screens.first { lane = .screen(sc.id) } else if let l = s.directory.visibleLocations(siteIds: church.siteIds).first { lane = .location(l.id) }
                }
                if !anchorWasSet { anchor = today; anchorWasSet = true }
            }
            loadError = nil
            try await loadRange(force: true)
        } catch {
            if !(error is CancellationError) { loadError = Formatting.message(for: error) }
        }
    }

    /// Loads the schedules around the visible days (a few weeks either side so paging is instant) unless they are already there.
    public func ensureLoaded() async {
        if source == nil { await reload(); return }
        do { try await loadRange(force: false) } catch { if !(error is CancellationError) { loadError = Formatting.message(for: error) } }
    }

    private func loadRange(force: Bool) async throws {
        let days = visibleDays
        let tz = timeZone
        guard let need = CalendarLoader.paddedRange(days: days, in: tz) else { return }
        if !force, let r = loadedRange, r.from <= need.from, r.to >= need.to { rebuild(); return }
        let from = SiteClock.instant(day: days[0].adding(days: -35), time: ClockTime(0), in: tz)
        let to = SiteClock.instant(day: days[days.count - 1].adding(days: 49), time: ClockTime(0), in: tz)
        let result = await CalendarLoader.loadRange(service: service, organizationId: church.id, modules: church.modules, from: from, to: to)
        try Task.checkCancellation()
        data.snapshots = result.snapshots
        warnings = (source?.warnings ?? []) + result.warnings
        loadedRange = (from, to)
        rebuild()
    }

    private func visibleChanged() {
        loadTask?.cancel()
        rebuild()
        loadTask = Task { await ensureLoaded() }
    }

    /// Recomputes blocks for the visible days from what is loaded.
    func rebuild() {
        let lane = resolvedLane
        let days = visibleDays
        events = CalendarEventBuilder.events(data: data, directory: directory, permissions: permissions, lane: lane, days: days)
        var byDay: [CalendarDay: [CalendarSegment]] = [:]
        var byId: [String: CalendarEvent] = [:]
        for e in events {
            byId[e.id] = e
            for s in CalendarSegments.split(eventId: e.id, start: e.start, end: e.end, in: lane.timeZone) where days.contains(s.day) { byDay[s.day, default: []].append(s) }
        }
        let geo = CalendarGeometry()
        var out: [CalendarDay: [PlacedSegment]] = [:]
        for (day, segs) in byDay {
            let cols = geo.columns(for: segs.map { ($0.startMinute, $0.endMinute) })
            out[day] = segs.enumerated().compactMap { i, s in byId[s.eventId].map { PlacedSegment(segment: s, event: $0, placement: cols[i]) } }
        }
        placed = out
        let defaultModule: String? = { if case .screen(let id) = lane.lane { return directory.screens.first { $0.id == id }?.screen.defaultModule }; return nil }()
        bands = CalendarBands.bands(rules: data.moduleRules, lane: lane, defaultModule: defaultModule, days: days)
    }

    // MARK: Create

    public func createRequest(day: CalendarDay, startMinute: Int, endMinute: Int) -> CalendarCreateRequest {
        let lane = resolvedLane
        let locs = directory.locations.map(\.id).filter(lane.locationIds.contains)
        return CalendarCreateRequest(day: day, startMinute: startMinute, endMinute: endMinute, lane: lane, locationIds: locs)
    }

    // MARK: Move and resize

    /// Persist a move or resize. `newStart` / `newEnd` are wall times in the lane's zone, already snapped.
    public func commit(_ event: CalendarEvent, newStart: WallTime, newEnd: WallTime) async {
        let plan = CalendarEditPlanner.plan(event: event, newStart: newStart, newEnd: newEnd, in: timeZone, organizationId: church.id)
        switch plan {
        case .unchanged: break
        case .rejected(let why): actionError = why
        case .apply(let change): await run(change)
        case .choose(let title, let message, let choices): pendingEdit = PendingCalendarEdit(event: event, title: title, message: message, choices: choices)
        }
    }

    public func run(_ change: CalendarChange) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await CalendarEditor.apply(change, service: service, organizationId: church.id)
            await reload(force: false)
        } catch {
            actionError = Formatting.message(for: error)
            await reload(force: false)
        }
    }

    /// Nudges for VoiceOver / keyboard: move or resize by whole steps.
    public func nudge(_ event: CalendarEvent, moveMinutes: Int = 0, resizeMinutes: Int = 0) async {
        let tz = timeZone
        let s = WallTime(event.start, in: tz).adding(minutes: moveMinutes)
        let e = WallTime(event.end, in: tz).adding(minutes: moveMinutes + resizeMinutes)
        await commit(event, newStart: s, newEnd: e)
    }
}
