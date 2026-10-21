import Foundation

// The calendar's data model and the logic that turns schedule rows into blocks on a grid. Everything here is pure (no UI, no network),
// so it is unit tested. Mirrors dashboard/src/calendar/CalendarPage.tsx and tz.ts. All clock times are in the SITE's time zone.

/// A wall-clock moment: a calendar day plus minutes after midnight (0...1440; 1440 = the next midnight). The grid works in wall time, so a
/// day always has 24 hours on screen, also on a daylight saving change day (like FullCalendar with the website's `toWall`).
public struct WallTime: Hashable, Comparable, Sendable {
    public var day: CalendarDay
    public var minutes: Int
    public init(day: CalendarDay, minutes: Int) { self.day = day; self.minutes = minutes }
    public init(_ date: Date, in tz: TimeZone) {
        day = SiteClock.day(of: date, in: tz)
        minutes = SiteClock.time(of: date, in: tz).minutes
    }
    /// Folds minutes outside 0..<1440 into the right day.
    public var normalized: WallTime {
        let extra = Int((Double(minutes) / 1440).rounded(.down))
        return extra == 0 ? self : WallTime(day: day.adding(days: extra), minutes: minutes - extra * 1440)
    }
    public func instant(in tz: TimeZone) -> Date {
        let w = normalized
        return SiteClock.instant(day: w.day, time: ClockTime(w.minutes / 60, w.minutes % 60), in: tz)
    }
    public func adding(minutes m: Int) -> WallTime { WallTime(day: day, minutes: minutes + m).normalized }
    public static func < (a: WallTime, b: WallTime) -> Bool { a.day != b.day ? a.day < b.day : a.minutes < b.minutes }
    /// Minutes from `other` to self (wall minutes).
    public func minutes(since other: WallTime) -> Int { daysBetween(other.day, day) * 1440 + minutes - other.minutes }
}

func daysBetween(_ a: CalendarDay, _ b: CalendarDay) -> Int {
    Int((b.noonUTC.timeIntervalSince(a.noonUTC) / 86_400).rounded())
}

public extension CalendarDay {
    /// Monday of the week containing this day (the web calendar starts weeks on Monday).
    var mondayOfWeek: CalendarDay { adding(days: -((weekday + 6) % 7)) }
    func days(since other: CalendarDay) -> Int { daysBetween(other, self) }
}

/// One block of an event on one day of the grid (an event that runs past midnight has one per day).
public struct CalendarSegment: Hashable, Sendable {
    public var eventId: String
    public var day: CalendarDay
    public var startMinute: Int
    public var endMinute: Int
    public var continuesBefore: Bool
    public var continuesAfter: Bool
    public init(eventId: String, day: CalendarDay, startMinute: Int, endMinute: Int, continuesBefore: Bool = false, continuesAfter: Bool = false) {
        self.eventId = eventId; self.day = day; self.startMinute = startMinute; self.endMinute = endMinute
        self.continuesBefore = continuesBefore; self.continuesAfter = continuesAfter
    }
}

public enum CalendarSegments {
    /// Splits [start, end) at wall midnights of `tz`. A real day may be 23 or 25 hours long; the grid still shows 24 wall hours.
    /// Zero-length events get a zero-length segment (the view draws a minimum height).
    public static func split(eventId: String, start: Date, end: Date, in tz: TimeZone) -> [CalendarSegment] {
        let end = max(end, start)
        let first = SiteClock.day(of: start, in: tz)
        let lastInstant = end > start ? end.addingTimeInterval(-1) : start
        let last = SiteClock.day(of: lastInstant, in: tz)
        var out: [CalendarSegment] = []
        var d = first
        var guardN = 0
        while d <= last, guardN < 60 {
            guardN += 1
            let dayStart = SiteClock.instant(day: d, time: ClockTime(0), in: tz)
            let nextStart = SiteClock.instant(day: d.adding(days: 1), time: ClockTime(0), in: tz)
            let s = max(start, dayStart)
            let e = min(end, nextStart)
            let sm = d == first ? SiteClock.time(of: s, in: tz).minutes : 0
            let em = e >= nextStart ? 1440 : (d == last ? SiteClock.time(of: e, in: tz).minutes : 1440)
            out.append(CalendarSegment(eventId: eventId, day: d, startMinute: sm, endMinute: max(em, sm), continuesBefore: d != first, continuesAfter: d != last))
            d = d.adding(days: 1)
        }
        return out
    }
}

// MARK: - Events

public enum CalendarEventStyle: String, CaseIterable, Sendable {
    case kidsOneTime, kidsRepeating, slidesOneTime, slidesRepeating, signage, moduleSwitch

    public var legend: String {
        switch self {
        case .kidsOneTime: return "Kids one-time"
        case .kidsRepeating: return "Kids repeating"
        case .slidesOneTime: return "Slides one-time"
        case .slidesRepeating: return "Slides repeating"
        case .signage: return "Signage"
        case .moduleSwitch: return "Module switch"
        }
    }
}

public struct CalendarEvent: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case oneOff(module: AppModule, table: ScheduleTable, schedule: DatedSchedule, openEnded: Bool)
        case occurrence(module: AppModule, table: ScheduleTable, series: RepeatingSeries, occurrence: SeriesOccurrence)
        case slot(SignageSlot)
        case moduleRule(ModuleRule)
    }
    public var id: String
    public var source: Source
    public var style: CalendarEventStyle
    public var title: String
    public var subtitle: String?
    public var start: Date
    public var end: Date
    public var locationId: UUID?
    public var editable: Bool
    public var lockReason: String?

    public var isRepeating: Bool {
        switch source { case .occurrence: return true; default: return false }
    }
    /// An open-ended one-off lasts until the next one in the room, so it cannot be resized.
    public var canResize: Bool {
        if case .oneOff(_, _, _, let open) = source { return !open }
        return true
    }
    /// Module of Kids/Slides/Signage items, nil for module switches.
    public var module: AppModule? {
        switch source {
        case .oneOff(let m, _, _, _), .occurrence(let m, _, _, _): return m
        case .slot: return .signage
        case .moduleRule: return nil
        }
    }
}

/// What the member may change. Mirrors the website (`canEditContent`, owners/admins for module switches, signage = all sites).
public struct CalendarPermissions: Equatable, Sendable {
    public var role: Role
    public var modules: [AppModule]
    public var siteIds: [UUID]?
    public init(role: Role, modules: [AppModule], siteIds: [UUID]? = nil) { self.role = role; self.modules = modules; self.siteIds = siteIds }
    public init(_ access: ChurchAccess) { self.init(role: access.role, modules: access.modules, siteIds: access.siteIds) }

    public var isAdmin: Bool { ContentPermissions.isAdmin(role) }
    public func canEdit(_ module: AppModule, siteId: UUID?) -> Bool {
        ContentPermissions.canEditContent(role: role, modules: modules, siteIds: siteIds, module: module, siteId: siteId)
    }
    public var canEditSignage: Bool { canEdit(.signage, siteId: nil) }
    public var canEditModuleRules: Bool { isAdmin }
    /// May this member create anything at all (the "+" button and drag-to-create)?
    public func canCreate(locations: [Location]) -> Bool {
        canEditSignage || isAdmin || locations.contains { loc in
            [AppModule.kids, .slides].contains { m in CalendarLocations.runs(m, loc) && canEdit(m, siteId: loc.siteId) }
        }
    }
}

public enum CalendarLocations {
    /// Can this location run content of this module? Slides use rooms tagged Slides, or Kids as well while nothing is tagged for Slides yet
    /// (`locationRuns` in dashboard/src/calendar/domain.ts).
    public static func runs(_ module: AppModule, _ loc: Location) -> Bool {
        let tags = loc.modules ?? []
        switch module {
        case .kids: return tags.contains("kids")
        case .slides: return tags.contains("slides") || tags.contains("kids")
        case .signage: return tags.contains("signage")
        }
    }
}

// MARK: - Lanes (what the calendar shows)

public enum CalendarLane: Hashable, Sendable {
    case all
    case location(UUID)
    case screen(UUID)
    case group(UUID)
}

/// A lane resolved against the church's screens: which locations, screens and groups it covers and the time zone it is shown in.
public struct ResolvedLane: Equatable, Sendable {
    public var lane: CalendarLane
    public var label: String
    public var timeZone: TimeZone
    public var screenIds: Set<UUID>
    public var groupIds: Set<UUID>
    public var locationIds: Set<UUID>
    /// More than one time zone is involved: times are shown in the first.
    public var mixedTimeZones: Bool
}

public struct CalendarDirectory: Sendable {
    public var screens: [ScreenInfo]
    public var groups: [ScreenGroup]
    public var locations: [Location]
    public var sites: [Site]
    public init(screens: [ScreenInfo] = [], groups: [ScreenGroup] = [], locations: [Location] = [], sites: [Site] = []) {
        self.screens = screens; self.groups = groups; self.locations = locations; self.sites = sites
    }

    public func timeZone(forLocation id: UUID?) -> TimeZone {
        let siteId = locations.first { $0.id == id }?.siteId
        let site = sites.first { $0.id == siteId } ?? sites.first
        return SiteClock.timeZone(id: site?.timezone)
    }
    public func locationName(_ id: UUID?) -> String { locations.first { $0.id == id }?.name ?? "" }
    public func screenName(_ id: UUID?) -> String { screens.first { $0.id == id }?.screen.displayName ?? "Screen" }

    /// Locations the member can see in the picker (all of them for members of all sites, else those of their sites).
    public func visibleLocations(siteIds: [UUID]?) -> [Location] {
        guard let siteIds else { return locations }
        return locations.filter { $0.siteId.map(siteIds.contains) ?? false }
    }

    public func resolve(_ lane: CalendarLane) -> ResolvedLane {
        func finish(label: String, screens: Set<UUID>, groups: Set<UUID>, locs: Set<UUID>) -> ResolvedLane {
            let ordered = locations.map(\.id).filter(locs.contains)
            let zones = ordered.map { timeZone(forLocation: $0).identifier }
            let first = zones.first.map { TimeZone(identifier: $0)! } ?? timeZone(forLocation: nil)
            return ResolvedLane(lane: lane, label: label, timeZone: first, screenIds: screens, groupIds: groups, locationIds: locs, mixedTimeZones: Set(zones).count > 1)
        }
        switch lane {
        case .all:
            return finish(label: "Everything", screens: Set(screens.map(\.id)), groups: Set(groups.map(\.id)), locs: Set(locations.map(\.id)))
        case .location(let id):
            let members = screens.filter { $0.screen.locationId == id }
            return finish(label: locationName(id), screens: Set(members.map(\.id)), groups: Set(members.compactMap { $0.screen.groupId }), locs: [id])
        case .screen(let id):
            let s = screens.first { $0.id == id }
            return finish(label: s?.screen.displayName ?? "Screen", screens: [id], groups: s?.screen.groupId.map { [$0] } ?? [], locs: s?.screen.locationId.map { [$0] } ?? [])
        case .group(let id):
            let members = screens.filter { $0.screen.groupId == id }
            return finish(label: groups.first { $0.id == id }?.name ?? "Group", screens: [], groups: [id], locs: Set(members.compactMap { $0.screen.locationId }))
        }
    }
}

// MARK: - Building events

public struct CalendarData: Sendable {
    public var snapshots: [AppModule: ScheduleSnapshot]
    public var moduleRules: [ModuleRule]
    public var names: [UUID: String]
    public init(snapshots: [AppModule: ScheduleSnapshot] = [:], moduleRules: [ModuleRule] = [], names: [UUID: String] = [:]) {
        self.snapshots = snapshots; self.moduleRules = moduleRules; self.names = names
    }
}

public enum CalendarEventBuilder {
    /// All blocks that touch `days` (consecutive days) for `lane`, in the lane's time zone.
    public static func events(data: CalendarData, directory: CalendarDirectory, permissions: CalendarPermissions, lane: ResolvedLane, days: [CalendarDay]) -> [CalendarEvent] {
        guard let firstDay = days.first, let lastDay = days.last else { return [] }
        let tz = lane.timeZone
        let rangeStart = SiteClock.instant(day: firstDay, time: ClockTime(0), in: tz)
        let rangeEnd = SiteClock.instant(day: lastDay.adding(days: 1), time: ClockTime(0), in: tz)
        let multiLocation = lane.locationIds.count > 1
        func name(_ id: UUID?, fallback: String) -> String { id.flatMap { data.names[$0] } ?? fallback }
        var out: [CalendarEvent] = []

        // Weekly rows on every visible day.
        func mine(screen: UUID?, group: UUID?) -> Bool {
            (screen.map(lane.screenIds.contains) ?? false) || (group.map(lane.groupIds.contains) ?? false)
        }
        func ruleSub(screen: UUID?, group: UUID?) -> String? {
            if let g = group { return "Group: " + (directory.groups.first { $0.id == g }?.name ?? "-") }
            if case .all = lane.lane { return directory.screenName(screen) }
            if case .location = lane.lane { return directory.screenName(screen) }
            if case .group = lane.lane { return directory.screenName(screen) }
            return nil
        }
        let slots = (data.snapshots[.signage]?.slots ?? []).filter { mine(screen: $0.screenId, group: $0.groupId) }
        let rules = data.moduleRules.filter { mine(screen: $0.screenId, group: $0.groupId) }
        for d in days {
            let dow = d.weekday
            for r in slots where r.days.contains(dow) {
                out.append(CalendarEvent(
                    id: "slot:\(r.id):\(d)", source: .slot(r), style: .signage, title: name(r.playlistId, fallback: "Unknown playlist"),
                    subtitle: ruleSub(screen: r.screenId, group: r.groupId), start: SiteClock.instant(day: d, time: r.startTime, in: tz),
                    end: ruleEnd(day: d, end: r.endTime, endOfDay: r.endIsEndOfDay, in: tz), locationId: nil, editable: permissions.canEditSignage,
                    lockReason: permissions.canEditSignage ? nil : "Signage slots can only be changed by editors with access to all sites."))
            }
            for r in rules where r.days.contains(dow) {
                let title = r.module == "off" ? "Screen off" : "Switch to \(AppModule(rawValue: r.module)?.displayName ?? r.module.capitalized)"
                out.append(CalendarEvent(
                    id: "mod:\(r.id):\(d)", source: .moduleRule(r), style: .moduleSwitch, title: title, subtitle: ruleSub(screen: r.screenId, group: r.groupId),
                    start: SiteClock.instant(day: d, time: r.startTime, in: tz), end: ruleEnd(day: d, end: r.endTime, endOfDay: r.endIsEndOfDay, in: tz),
                    locationId: nil, editable: permissions.canEditModuleRules,
                    lockReason: permissions.canEditModuleRules ? nil : "Only owners and admins can change which module a screen runs."))
            }
        }

        // Kids and Slides: dated rows and repeating occurrences.
        for module in [AppModule.kids, .slides] {
            guard let snap = data.snapshots[module], let datedTable = ScheduleTable.dated(module), let seriesTable = ScheduleTable.series(module) else { continue }
            let sorted = snap.dated.sorted { $0.startsAt < $1.startsAt }
            for s in sorted where lane.locationIds.contains(s.locationId) {
                // An open-ended one-off lasts until the next one in that room, else an hour on the grid.
                let open = s.endsAt == nil
                let next = sorted.first { $0.locationId == s.locationId && $0.startsAt > s.startsAt }
                let end = s.endsAt ?? next?.startsAt ?? s.startsAt.addingTimeInterval(3600)
                guard s.startsAt < rangeEnd, end > rangeStart else { continue }
                let siteId = directory.locations.first { $0.id == s.locationId }?.siteId
                let can = permissions.canEdit(module, siteId: siteId)
                out.append(CalendarEvent(
                    id: "\(module.rawValue)-one:\(s.id)", source: .oneOff(module: module, table: datedTable, schedule: s, openEnded: open), style: module == .kids ? .kidsOneTime : .slidesOneTime,
                    title: name(s.itemId, fallback: module == .slides ? "Unknown deck" : "Unknown playlist"), subtitle: multiLocation ? directory.locationName(s.locationId) : nil,
                    start: s.startsAt, end: end, locationId: s.locationId, editable: can, lockReason: can ? nil : "\(module.displayName) schedules need editor access to this site."))
            }
            for o in snap.occurrences where lane.locationIds.contains(o.locationId) {
                guard let series = snap.series.first(where: { $0.id == o.seriesId }), o.startsAt < rangeEnd, o.endsAt > rangeStart else { continue }
                let siteId = directory.locations.first { $0.id == o.locationId }?.siteId
                let sameZone = directory.timeZone(forLocation: o.locationId).identifier == tz.identifier
                let can = permissions.canEdit(module, siteId: siteId) && sameZone
                let item = name(o.itemId, fallback: module == .slides ? "Unknown deck" : "Unknown playlist")
                let sub = (series.name?.isEmpty == false ? series.name : nil) ?? (multiLocation ? directory.locationName(o.locationId) : nil)
                out.append(CalendarEvent(
                    id: "\(module.rawValue)-ser:\(o.seriesId):\(o.onDate)", source: .occurrence(module: module, table: seriesTable, series: series, occurrence: o),
                    style: module == .kids ? .kidsRepeating : .slidesRepeating,
                    title: o.isOverride ? "\(item) (this date)" : o.occurrenceNo.map { "Week \($0): \(item)" } ?? item, subtitle: sub, start: o.startsAt, end: o.endsAt,
                    locationId: o.locationId, editable: can,
                    lockReason: can ? nil : (sameZone ? "\(module.displayName) schedules need editor access to this site." : "This repeating schedule is in a different time zone than the one shown, so it can't be edited here.")))
            }
        }
        return out.sorted { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
    }


    /// A rule's end on `day`: 23:59 / end of day means the next midnight.
    public static func ruleEnd(day: CalendarDay, end: ClockTime, endOfDay: Bool, in tz: TimeZone) -> Date {
        (endOfDay || end >= ClockTime(23, 59))
            ? SiteClock.instant(day: day.adding(days: 1), time: ClockTime(0), in: tz)
            : SiteClock.instant(day: day, time: end, in: tz)
    }
}

// MARK: - Module bands (screen and group lanes)

/// Which module a screen runs when, as tinted bands behind the grid (a screen or group view only). Port of the `band` events in
/// CalendarPage.tsx: the winning rule per stretch of the day is the highest priority, then the newest; no rule = the screen's default.
public struct CalendarBand: Hashable, Sendable {
    public var day: CalendarDay
    public var fromMinute: Int
    public var toMinute: Int
    public var module: String
}

public enum CalendarBands {
    public static func bands(rules: [ModuleRule], lane: ResolvedLane, defaultModule: String?, days: [CalendarDay]) -> [CalendarBand] {
        switch lane.lane { case .screen, .group: break; default: return [] }
        let mine = rules.filter { r in (r.screenId.map(lane.screenIds.contains) ?? false) || (r.groupId.map(lane.groupIds.contains) ?? false) }
        func end(_ r: ModuleRule) -> Int { (r.endIsEndOfDay || r.endTime >= ClockTime(23, 59)) ? 1440 : r.endTime.minutes }
        var out: [CalendarBand] = []
        for d in days {
            let todays = mine.filter { $0.days.contains(d.weekday) }
            let cuts = Set([0, 1440] + todays.flatMap { [$0.startTime.minutes, end($0)] }).sorted()
            var run: CalendarBand?
            for i in 0..<(cuts.count - 1) {
                let (from, to) = (cuts[i], cuts[i + 1])
                let winner = todays.filter { $0.startTime.minutes <= from && from < end($0) }
                    .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.createdAt > $1.createdAt }.first
                let module = winner?.module ?? defaultModule
                if var r = run, r.module == module { r.toMinute = to; run = r; continue }
                if let r = run { out.append(r) }
                run = module.map { CalendarBand(day: d, fromMinute: from, toMinute: to, module: $0) }
            }
            if let r = run { out.append(r) }
        }
        return out
    }
}
