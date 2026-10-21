import Foundation

// Scheduling logic shared by the phone and the tests: calendar days, wall-clock times in a site's time zone, the sheet's form state,
// the rows it writes, the expansion of repeating schedules and the overlap hints. Mirrors the website (dashboard/src/slides/DeckSeriesManager.tsx,
// calendar/SeriesManager.tsx, ScheduleRules.tsx, calendar/tz.ts) and the SQL (kids_series_expand / deck_series_expand).

// MARK: - Calendar day and clock time

/// A calendar date without a time zone ("2026-10-25"), like a Postgres `date`.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int, month: Int, day: Int
    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    /// "2026-10-25"
    public init?(string: String) {
        let p = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        self.init(year: p[0], month: p[1], day: p[2])
    }

    public var string: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { string }
    public static func < (a: CalendarDay, b: CalendarDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    static var gmt: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

    /// 0 = Sunday ... 6 = Saturday (like the database).
    public var weekday: Int { (CalendarDay.gmt.component(.weekday, from: noonUTC) + 6) % 7 }
    public var noonUTC: Date { CalendarDay.gmt.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }

    public func adding(days n: Int) -> CalendarDay {
        let d = CalendarDay.gmt.date(byAdding: .day, value: n, to: noonUTC)!
        let c = CalendarDay.gmt.dateComponents([.year, .month, .day], from: d)
        return CalendarDay(year: c.year!, month: c.month!, day: c.day!)
    }
}

/// A wall-clock time ("09:00"), no date, no zone.
public struct ClockTime: Hashable, Comparable, Sendable {
    public var hour: Int, minute: Int
    public init(_ hour: Int, _ minute: Int = 0) { self.hour = hour; self.minute = minute }
    /// Reads "08:00", "08:00:00" or "23:59:59".
    public init?(db: String) {
        let p = db.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2, (0...23).contains(p[0]), (0...59).contains(p[1]) else { return nil }
        self.init(p[0], p[1])
    }
    public var minutes: Int { hour * 60 + minute }
    /// "08:00"
    public var hhmm: String { String(format: "%02d:%02d", hour, minute) }
    /// The value written to a `time` column. 23:59 is stored as 23:59:59 (end of day) like the website.
    public var dbString: String { hhmm == "23:59" ? "23:59:59" : hhmm }
    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutes < b.minutes }
}

public enum ScheduleDays {
    public static let shortNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    public static let fullNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    public static let everyDay: Set<Int> = Set(0...6)
    public static let weekdays: Set<Int> = [1, 2, 3, 4, 5]
    public static let weekend: Set<Int> = [0, 6]

    /// "daily", "Mon-Fri", "Sun", "Sat, Sun" ... (same as `daysLabel` on the website; the week starts on Sunday).
    public static func label(_ days: some Collection<Int>) -> String {
        let on = Set(days).filter { (0...6).contains($0) }.sorted()
        if on.count == 7 { return "daily" }
        var parts: [String] = []
        var i = 0
        while i < on.count {
            var j = i
            while j + 1 < on.count, on[j + 1] == on[j] + 1 { j += 1 }
            parts.append(j - i >= 2 ? "\(shortNames[on[i]])-\(shortNames[on[j]])" : on[i...j].map { shortNames[$0] }.joined(separator: ", "))
            i = j + 1
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Site time zone

/// Wall-clock times in the SITE's time zone (not the phone's). Uses Foundation's time zone database, so daylight saving is right:
/// a Sunday 9:00 stays 9:00 on both sides of a clock change. A time that does not exist (spring forward) lands later,
/// an ambiguous one (fall back) takes the first, like `fromWall` in the website's tz.ts.
public enum SiteClock {
    /// The zone the database falls back to when a site has none (`coalesce(st.timezone, 'America/Toronto')`).
    public static let fallbackZoneId = "America/Toronto"

    public static func timeZone(id: String?) -> TimeZone {
        if let id, !id.isEmpty, let tz = TimeZone(identifier: id) { return tz }
        return TimeZone(identifier: fallbackZoneId) ?? .current
    }

    static func calendar(_ tz: TimeZone) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c }

    /// The real instant of `time` on `day` in `tz`.
    public static func instant(day: CalendarDay, time: ClockTime, in tz: TimeZone) -> Date {
        let cal = calendar(tz)
        let comps = DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute, second: 0)
        if let d = cal.date(from: comps) {
            // A skipped hour is pushed forward by Foundation; make sure the wall clock never reads earlier than asked.
            return d
        }
        // Should not happen; fall back to noon-based arithmetic.
        return cal.startOfDay(for: day.noonUTC).addingTimeInterval(TimeInterval(time.minutes * 60))
    }

    /// The calendar day an instant falls on in `tz`.
    public static func day(of date: Date, in tz: TimeZone) -> CalendarDay {
        let c = calendar(tz).dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func time(of date: Date, in tz: TimeZone) -> ClockTime {
        let c = calendar(tz).dateComponents([.hour, .minute], from: date)
        return ClockTime(c.hour!, c.minute!)
    }

    /// "Eastern Time (America/Toronto)"
    public static func displayName(_ tz: TimeZone) -> String {
        let long = tz.localizedName(for: .standard, locale: .current) ?? tz.identifier
        return "\(long) (\(tz.identifier))"
    }

    /// True when `tz` has a different UTC offset than the device's zone (now or half a year from now), so Toronto vs New York is fine
    /// but Toronto vs Vancouver is flagged (the highlight in the sheet).
    public static func differsFromDevice(_ tz: TimeZone, device: TimeZone = .current, at date: Date = Date()) -> Bool {
        let later = date.addingTimeInterval(182 * 86_400)
        return tz.secondsFromGMT(for: date) != device.secondsFromGMT(for: date) || tz.secondsFromGMT(for: later) != device.secondsFromGMT(for: later)
    }

    // Pickers: SwiftUI date pickers edit "wall" dates, a Date whose UTC fields hold the clock time (set the picker's time zone to UTC),
    // so no device zone or daylight saving gap can alter what the person typed.
    public static func wallDate(day: CalendarDay, time: ClockTime) -> Date {
        CalendarDay.gmt.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute))!
    }
    public static func wallParts(_ date: Date) -> (day: CalendarDay, time: ClockTime) {
        let c = CalendarDay.gmt.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (CalendarDay(year: c.year!, month: c.month!, day: c.day!), ClockTime(c.hour!, c.minute!))
    }
}

// MARK: - Tables and rows

/// The tables the sheet writes to.
public enum ScheduleTable: String, Sendable, CaseIterable {
    case deckSchedules = "deck_schedules", deckSeries = "deck_series"
    case kidsSchedules = "schedules", kidsSeries = "kids_series"
    case signageSlots = "signage_slots"

    public static func dated(_ module: AppModule) -> ScheduleTable? { module == .slides ? .deckSchedules : module == .kids ? .kidsSchedules : nil }
    public static func series(_ module: AppModule) -> ScheduleTable? { module == .slides ? .deckSeries : module == .kids ? .kidsSeries : nil }
    /// Column holding the item id of a dated row ("deck_id" / "playlist_id").
    public var itemColumn: String { self == .deckSchedules ? "deck_id" : "playlist_id" }
    /// Column holding the rotation of a series row ("deck_ids" / "playlist_ids").
    public var rotationColumn: String { self == .deckSeries ? "deck_ids" : "playlist_ids" }
    public var exceptionsTable: String? { self == .deckSeries ? "deck_series_exceptions" : self == .kidsSeries ? "kids_series_exceptions" : nil }
}

/// One row to insert.
public struct NewScheduleRow: Equatable, Sendable {
    public var table: ScheduleTable
    public var values: [String: RawJSON]
    public init(table: ScheduleTable, values: [String: RawJSON]) { self.table = table; self.values = values }
}

public enum OnEnd: String, CaseIterable, Sendable, Hashable { case loop, stop }

// MARK: - Read models

public struct DatedSchedule: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var locationId: UUID
    public var itemId: UUID
    public var startsAt: Date
    public var endsAt: Date?
    public init(id: UUID, locationId: UUID, itemId: UUID, startsAt: Date, endsAt: Date?) {
        self.id = id; self.locationId = locationId; self.itemId = itemId; self.startsAt = startsAt; self.endsAt = endsAt
    }
}

public struct RepeatingSeries: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var locationId: UUID
    public var name: String?
    public var days: [Int]
    public var startTime: ClockTime
    public var endTime: ClockTime
    public var startDate: CalendarDay
    public var endDate: CalendarDay?
    public var itemIds: [UUID]
    public var onEnd: OnEnd
    public init(id: UUID, locationId: UUID, name: String? = nil, days: [Int], startTime: ClockTime, endTime: ClockTime, startDate: CalendarDay,
                endDate: CalendarDay? = nil, itemIds: [UUID], onEnd: OnEnd = .loop) {
        self.id = id; self.locationId = locationId; self.name = name; self.days = days; self.startTime = startTime; self.endTime = endTime
        self.startDate = startDate; self.endDate = endDate; self.itemIds = itemIds; self.onEnd = onEnd
    }
}

public struct SeriesOccurrence: Hashable, Identifiable, Sendable {
    public var seriesId: UUID
    public var locationId: UUID
    public var onDate: CalendarDay
    public var startsAt: Date
    public var endsAt: Date
    public var itemId: UUID?
    public var occurrenceNo: Int?
    /// True when a "changed date" exception replaced the item for this date (`is_override` of the occurrences function).
    public var isOverride: Bool
    public var id: String { "\(seriesId)-\(onDate)" }
    public init(seriesId: UUID, locationId: UUID, onDate: CalendarDay, startsAt: Date, endsAt: Date, itemId: UUID?, occurrenceNo: Int? = nil, isOverride: Bool = false) {
        self.seriesId = seriesId; self.locationId = locationId; self.onDate = onDate; self.startsAt = startsAt; self.endsAt = endsAt
        self.itemId = itemId; self.occurrenceNo = occurrenceNo; self.isOverride = isOverride
    }
}

public struct SignageSlot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var screenId: UUID?
    public var groupId: UUID?
    public var playlistId: UUID
    public var days: [Int]
    public var startTime: ClockTime
    public var endTime: ClockTime
    public var endIsEndOfDay: Bool
    public var priority: Int
    public init(id: UUID, screenId: UUID? = nil, groupId: UUID? = nil, playlistId: UUID, days: [Int], startTime: ClockTime, endTime: ClockTime,
                endIsEndOfDay: Bool = false, priority: Int = 0) {
        self.id = id; self.screenId = screenId; self.groupId = groupId; self.playlistId = playlistId; self.days = days
        self.startTime = startTime; self.endTime = endTime; self.endIsEndOfDay = endIsEndOfDay; self.priority = priority
    }
    public var target: SignageTargetRef { SignageTargetRef(screenId: screenId, groupId: groupId) }
}

public struct ScreenGroup: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}

/// A screen or a group of screens (exactly one is set).
public struct SignageTargetRef: Hashable, Sendable {
    public var screenId: UUID?
    public var groupId: UUID?
    public init(screenId: UUID? = nil, groupId: UUID? = nil) { self.screenId = screenId; self.groupId = groupId }
    public static func screen(_ id: UUID) -> SignageTargetRef { .init(screenId: id) }
    public static func group(_ id: UUID) -> SignageTargetRef { .init(groupId: id) }
}

/// Everything the sheet needs to know about existing schedules of one module.
/// Kids/Slides: dated rows (not yet over), all repeating series and their occurrences for the next 14 days. Signage: the slots.
public struct ScheduleSnapshot: Sendable {
    public var dated: [DatedSchedule]
    public var series: [RepeatingSeries]
    public var occurrences: [SeriesOccurrence]
    public var slots: [SignageSlot]
    public init(dated: [DatedSchedule] = [], series: [RepeatingSeries] = [], occurrences: [SeriesOccurrence] = [], slots: [SignageSlot] = []) {
        self.dated = dated; self.series = series; self.occurrences = occurrences; self.slots = slots
    }
    public static let empty = ScheduleSnapshot()
}

// MARK: - Form state and rows (Kids playlist, Slides deck)

/// What the person entered for a deck or Kids playlist: one-off or weekly, in the SITE's wall-clock time.
public struct ScheduleForm: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable { case once, repeating }
    public var mode: Mode = .once
    public var locationIds: Set<UUID> = []
    // Just once
    public var day: CalendarDay
    public var start: ClockTime
    public var hasEnd: Bool
    public var end: ClockTime
    // Repeating
    public var weekdays: Set<Int>
    public var startDate: CalendarDay
    public var hasEndDate: Bool = false
    public var endDate: CalendarDay
    /// The rotation: one item id per week. Starts as `[target]`.
    public var rotation: [UUID]
    public var onEnd: OnEnd = .loop
    public var name: String = ""

    /// Defaults like the website: next Sunday, 9:00 for a one-off, 8:00-13:00 for a weekly repeat starting that Sunday.
    public static func initial(for target: ScheduleTarget, now: Date = Date(), in tz: TimeZone) -> ScheduleForm {
        let today = SiteClock.day(of: now, in: tz)
        let ahead = (7 - today.weekday) % 7 == 0 ? 7 : (7 - today.weekday) % 7
        let sunday = today.adding(days: ahead)
        return ScheduleForm(day: sunday, start: ClockTime(9), hasEnd: true, end: ClockTime(12), weekdays: [0], startDate: sunday,
                            endDate: sunday.adding(days: 84), rotation: [target.id])
    }

    public init(day: CalendarDay, start: ClockTime, hasEnd: Bool, end: ClockTime, weekdays: Set<Int>, startDate: CalendarDay,
                endDate: CalendarDay, rotation: [UUID]) {
        self.day = day; self.start = start; self.hasEnd = hasEnd; self.end = end; self.weekdays = weekdays
        self.startDate = startDate; self.endDate = endDate; self.rotation = rotation
    }

    /// Why the form cannot be saved yet (text for the person), or nil.
    public var problem: String? {
        if locationIds.isEmpty { return "Choose at least one location." }
        switch mode {
        case .once:
            if hasEnd && end <= start { return "The end time must be after the start time." }
        case .repeating:
            if weekdays.isEmpty { return "Choose at least one day." }
            if end <= start { return "The end time must be after the start time." }
            if hasEndDate && endDate < startDate { return "The end date must not be before the start date." }
            if rotation.isEmpty { return "Choose an item for every week." }
        }
        return nil
    }
}

public enum ScheduleRowBuilder {
    /// The rows for a deck or Kids playlist: one per location (a batch). `timeZone` gives the site zone of a location.
    /// Dated rows hold instants (computed per location, so locations in different zones get different instants);
    /// repeating rows hold the wall-clock times and dates, the database expands them in the site's zone.
    public static func rows(target: ScheduleTarget, form: ScheduleForm, organizationId: UUID, orderedLocations: [UUID], timeZone: (UUID) -> TimeZone) throws -> [NewScheduleRow] {
        guard target.module != .signage else { throw ChurchError("Signage playlists are scheduled on screens.") }
        if let p = form.problem { throw ChurchError(p) }
        let module = target.module
        let locations = orderedLocations.filter { form.locationIds.contains($0) }
        var out: [NewScheduleRow] = []
        for loc in locations {
            switch form.mode {
            case .once:
                guard let table = ScheduleTable.dated(module) else { continue }
                let tz = timeZone(loc)
                var v: [String: RawJSON] = [
                    "organization_id": .string(lower(organizationId)), "location_id": .string(lower(loc)), table.itemColumn: .string(lower(target.id)),
                    "starts_at": .string(ChurchJSON.formatTimestamp(SiteClock.instant(day: form.day, time: form.start, in: tz))),
                ]
                if form.hasEnd { v["ends_at"] = .string(ChurchJSON.formatTimestamp(SiteClock.instant(day: form.day, time: form.end, in: tz))) }
                out.append(NewScheduleRow(table: table, values: v))
            case .repeating:
                guard let table = ScheduleTable.series(module) else { continue }
                var v: [String: RawJSON] = [
                    "organization_id": .string(lower(organizationId)), "location_id": .string(lower(loc)),
                    "days": .array(form.weekdays.sorted().map { .number(Double($0)) }),
                    "start_time": .string(form.start.hhmm), "end_time": .string(form.end.dbString),
                    "start_date": .string(form.startDate.string),
                    table.rotationColumn: .array(form.rotation.map { .string(lower($0)) }),
                    "on_end": .string(form.onEnd.rawValue),
                ]
                let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { v["name"] = .string(name) }
                if form.hasEndDate { v["end_date"] = .string(form.endDate.string) }
                out.append(NewScheduleRow(table: table, values: v))
            }
        }
        return out
    }

    static func lower(_ u: UUID) -> String { u.uuidString.lowercased() }
}

// MARK: - Signage

public struct SignageForm: Equatable, Sendable {
    public var targets: [SignageTargetRef] = []
    public var weekdays: Set<Int> = ScheduleDays.everyDay
    public var start = ClockTime(0)
    public var end = ClockTime(23, 59)
    public var higherPriority = false
    public init() {}

    public var problem: String? {
        if targets.isEmpty { return "Choose a screen or a group." }
        if weekdays.isEmpty { return "Choose at least one day." }
        if end <= start { return "The end time must be after the start time." }
        return nil
    }
}

public enum SignagePriority {
    /// 0 normally. With "higher priority than overlapping rules": the highest priority this screen or group already has, plus one.
    public static func value(existing: [SignageSlot], for target: SignageTargetRef, higher: Bool) -> Int {
        guard higher else { return 0 }
        let mine = existing.filter { $0.target == target }
        return (mine.map(\.priority).max() ?? 0) + 1
    }
}

public extension ScheduleRowBuilder {
    /// One `signage_slots` row per chosen screen or group. `end` 23:59 is stored as 23:59:59.
    static func slotRows(playlistId: UUID, form: SignageForm, organizationId: UUID, existing: [SignageSlot]) throws -> [NewScheduleRow] {
        if let p = form.problem { throw ChurchError(p) }
        return form.targets.map { t in
            var v: [String: RawJSON] = [
                "organization_id": .string(lower(organizationId)), "playlist_id": .string(lower(playlistId)),
                "days": .array(form.weekdays.sorted().map { .number(Double($0)) }),
                "start_time": .string(form.start.dbString), "end_time": .string(form.end.dbString),
                "priority": .number(Double(SignagePriority.value(existing: existing, for: t, higher: form.higherPriority))),
            ]
            if let s = t.screenId { v["screen_id"] = .string(lower(s)) }
            if let g = t.groupId { v["group_id"] = .string(lower(g)) }
            return NewScheduleRow(table: .signageSlots, values: v)
        }
    }
}

// MARK: - Repeating schedules: occurrences

public enum SeriesExpander {
    /// Occurrences of one series that overlap [from, to], like `kids_series_expand` in SQL:
    ///  - dates from `startDate` (to `endDate`), on the chosen weekdays, wall-clock times in `tz` (daylight saving safe);
    ///  - a skipped date does not happen and does not use up a week: the rotation waits;
    ///  - `loop` wraps around the rotation, `stop` ends after the last item.
    public static func occurrences(of s: RepeatingSeries, skipped: Set<CalendarDay> = [], from: Date, to: Date, in tz: TimeZone) -> [SeriesOccurrence] {
        guard !s.itemIds.isEmpty, !s.days.isEmpty else { return [] }
        let lastDay = min(s.endDate ?? SiteClock.day(of: to, in: tz), SiteClock.day(of: to, in: tz))
        var out: [SeriesOccurrence] = []
        var d = s.startDate
        var n = 0
        let days = Set(s.days)
        var guardCount = 0
        while d <= lastDay, guardCount < 20_000 {
            guardCount += 1
            defer { d = d.adding(days: 1) }
            guard days.contains(d.weekday), !skipped.contains(d) else { continue }
            n += 1
            let item: UUID?
            if s.onEnd == .loop || n <= s.itemIds.count { item = s.itemIds[(n - 1) % s.itemIds.count] } else { item = nil }
            guard let item else { continue }
            let a = SiteClock.instant(day: d, time: s.startTime, in: tz), b = SiteClock.instant(day: d, time: s.endTime, in: tz)
            if b > from && a < to {
                out.append(SeriesOccurrence(seriesId: s.id, locationId: s.locationId, onDate: d, startsAt: a, endsAt: b, itemId: item, occurrenceNo: n))
            }
        }
        return out
    }
}

// MARK: - Text and overlap hints

public enum ScheduleText {
    private static func formatter(_ style: (DateFormatter) -> Void, tz: TimeZone) -> DateFormatter {
        let f = DateFormatter(); f.timeZone = tz; style(f); return f
    }
    /// "9:00 AM" (or 09:00 in 24-hour regions) for a wall-clock time.
    public static func time(_ t: ClockTime) -> String {
        formatter({ $0.timeStyle = .short; $0.dateStyle = .none }, tz: TimeZone(secondsFromGMT: 0)!).string(from: SiteClock.wallDate(day: CalendarDay(year: 2026, month: 1, day: 1), time: t))
    }
    public static func timeRange(_ a: ClockTime, _ b: ClockTime, endOfDay: Bool = false) -> String {
        (a == ClockTime(0) && (b == ClockTime(23, 59) || endOfDay)) ? "all day" : "\(time(a)) to \(time(b))"
    }
    /// "Sun, Oct 25"
    public static func day(_ d: CalendarDay) -> String {
        formatter({ $0.setLocalizedDateFormatFromTemplate("EEEMMMd") }, tz: TimeZone(secondsFromGMT: 0)!).string(from: d.noonUTC)
    }
    /// "Sun, Oct 25, 9:00 AM"
    public static func when(_ date: Date, in tz: TimeZone) -> String {
        formatter({ $0.setLocalizedDateFormatFromTemplate("EEEMMMdjmm") }, tz: tz).string(from: date)
    }
    /// "9:00 AM"
    public static func clock(_ date: Date, in tz: TimeZone) -> String { formatter({ $0.timeStyle = .short; $0.dateStyle = .none }, tz: tz).string(from: date) }
    public static func rangeText(_ a: Date, _ b: Date?, in tz: TimeZone) -> String {
        guard let b else { return when(a, in: tz) + ", until the next one" }
        return SiteClock.day(of: a, in: tz) == SiteClock.day(of: b, in: tz) ? "\(when(a, in: tz)) to \(clock(b, in: tz))" : "\(when(a, in: tz)) to \(when(b, in: tz))"
    }
}

public enum ScheduleOverlap {
    /// Short, non-blocking warnings about schedules already at the same locations. Highest priority / the one that started last wins
    /// on the TV; a one-off replaces an overlapping repeat. Returns at most `limit` lines.
    public static func hints(target: ScheduleTarget, form: ScheduleForm, snapshot: ScheduleSnapshot, itemName: (UUID) -> String,
                             locationName: (UUID) -> String, timeZone: (UUID) -> TimeZone, orderedLocations: [UUID], limit: Int = 4) -> [String] {
        guard target.module != .signage, form.problem == nil else { return [] }
        var out: [String] = []
        for loc in orderedLocations where form.locationIds.contains(loc) {
            let tz = timeZone(loc)
            let place = locationName(loc)
            switch form.mode {
            case .once:
                let a = SiteClock.instant(day: form.day, time: form.start, in: tz)
                let b: Date? = form.hasEnd ? SiteClock.instant(day: form.day, time: form.end, in: tz) : nil
                for e in snapshot.dated where e.locationId == loc && intervalsOverlap(a, b, e.startsAt, e.endsAt) {
                    out.append("\(place): “\(itemName(e.itemId))” is already scheduled \(ScheduleText.rangeText(e.startsAt, e.endsAt, in: tz)). The one that starts later takes over.")
                }
                for s in snapshot.series where s.locationId == loc {
                    let skipped: Set<CalendarDay> = []
                    let to = b ?? SiteClock.instant(day: form.day.adding(days: 1), time: ClockTime(0), in: tz)
                    if SeriesExpander.occurrences(of: s, skipped: skipped, from: a, to: to, in: tz).contains(where: { intervalsOverlap(a, b, $0.startsAt, $0.endsAt) }) {
                        out.append("\(place): this replaces the repeating “\(s.name?.isEmpty == false ? s.name! : itemName(s.itemIds[0]))” that day (\(ScheduleDays.label(s.days)), \(ScheduleText.timeRange(s.startTime, s.endTime))).")
                    }
                }
            case .repeating:
                let newEnd: CalendarDay? = form.hasEndDate ? form.endDate : nil
                for s in snapshot.series where s.locationId == loc {
                    let datesOverlap = form.startDate <= (s.endDate ?? .distantFuture) && s.startDate <= (newEnd ?? .distantFuture)
                    let sharedDay = !Set(s.days).isDisjoint(with: form.weekdays)
                    let timesOverlap = form.start < s.endTime && s.startTime < form.end
                    if datesOverlap && sharedDay && timesOverlap {
                        out.append("\(place): the repeating “\(s.name?.isEmpty == false ? s.name! : itemName(s.itemIds[0]))” (\(ScheduleDays.label(s.days)), \(ScheduleText.timeRange(s.startTime, s.endTime))) overlaps. The one that starts later takes over.")
                    }
                }
                let probe = RepeatingSeries(id: UUID(), locationId: loc, days: Array(form.weekdays), startTime: form.start, endTime: form.end,
                                            startDate: form.startDate, endDate: newEnd, itemIds: [target.id], onEnd: .loop)
                for e in snapshot.dated where e.locationId == loc {
                    let to = e.endsAt ?? e.startsAt.addingTimeInterval(86_400)
                    if !SeriesExpander.occurrences(of: probe, from: e.startsAt, to: to, in: tz).isEmpty {
                        out.append("\(place): the one-off “\(itemName(e.itemId))” on \(ScheduleText.when(e.startsAt, in: tz)) replaces this repeat on that date.")
                    }
                }
            }
        }
        return trimmed(out, limit)
    }

    /// Existing slots of the same screens or groups that share a day and time with the new slot.
    public static func signageHints(form: SignageForm, existing: [SignageSlot], itemName: (UUID) -> String, targetName: (SignageTargetRef) -> String, limit: Int = 4) -> [String] {
        guard form.problem == nil else { return [] }
        var out: [String] = []
        for t in form.targets {
            for s in existing where s.target == t {
                let sharedDay = !Set(s.days).isDisjoint(with: form.weekdays)
                if sharedDay && form.start < s.endTime && s.startTime < form.end {
                    out.append("\(targetName(t)): overlaps “\(itemName(s.playlistId))” (\(ScheduleDays.label(s.days)), \(ScheduleText.timeRange(s.startTime, s.endTime, endOfDay: s.endIsEndOfDay)), priority \(s.priority)). The highest priority wins; with equal priority the newest does.")
                }
            }
        }
        return trimmed(out, limit)
    }

    static func intervalsOverlap(_ a: Date, _ b: Date?, _ c: Date, _ d: Date?) -> Bool {
        a < (d ?? .distantFuture) && c < (b ?? .distantFuture)
    }
    static func trimmed(_ lines: [String], _ limit: Int) -> [String] {
        guard lines.count > limit else { return lines }
        return Array(lines.prefix(limit)) + ["and \(lines.count - limit) more overlapping schedules."]
    }
}

extension CalendarDay {
    static let distantFuture = CalendarDay(year: 9999, month: 12, day: 31)
}
