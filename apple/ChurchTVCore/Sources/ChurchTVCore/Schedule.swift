import Foundation

/// One line of the read-only "Today" overview.
public struct ScheduleEntry: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable { case oneOff, repeating, moduleRule }
    public let id: String
    public let screenId: UUID
    public let module: AppModule
    public let title: String
    public let starts: Date
    public let ends: Date?
    public let source: Source
    public init(id: String, screenId: UUID, module: AppModule, title: String, starts: Date, ends: Date?, source: Source) {
        self.id = id; self.screenId = screenId; self.module = module; self.title = title
        self.starts = starts; self.ends = ends; self.source = source
    }
}

// Raw rows used to build the schedule.
struct DeckScheduleRow: Decodable { let id: UUID; let locationId: UUID; let deckId: UUID; let startsAt: Date; let endsAt: Date? }
struct KidsScheduleRow: Decodable { let id: UUID; let locationId: UUID; let playlistId: UUID; let startsAt: Date; let endsAt: Date? }
/// Row of the *_series_occurrences RPCs (deck_id or playlist_id is present depending on the function).
struct OccurrenceRow: Decodable {
    let seriesId: UUID; let locationId: UUID; let startsAt: Date; let endsAt: Date?
    let deckId: UUID?; let playlistId: UUID?; let occurrenceNo: Int?
}

public enum ScheduleBuilder {
    /// Start and end of "today" in a time zone.
    public static func dayBounds(now: Date, timeZone: TimeZone) -> (Date, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: now)
        return (start, cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
    }

    /// Keep entries that overlap [from, to), sorted by start time.
    static func overlapping(_ entries: [ScheduleEntry], from: Date, to: Date) -> [ScheduleEntry] {
        entries.filter { $0.starts < to && ($0.ends ?? .distantFuture) > from }.sorted { $0.starts < $1.starts }
    }
}

extension ScheduleBuilder {
    /// "08:30:00" -> that time on the day starting at `dayStart`.
    static func time(_ hhmmss: String, on dayStart: Date, calendar: Calendar) -> Date? {
        let parts = hhmmss.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: parts.count > 2 ? parts[2] : 0, of: dayStart)
    }

    /// Per screen: keep today's entries (in the screen's time zone), end open-ended one-offs where the next one starts, sort.
    public static func today(_ entries: [ScheduleEntry], screens: [ScreenInfo], now: Date) -> [ScheduleEntry] {
        var out: [ScheduleEntry] = []
        for s in screens {
            let (from, to) = dayBounds(now: now, timeZone: s.timeZone)
            let mine = entries.filter { $0.screenId == s.id }.sorted { $0.starts < $1.starts }
            // A one-off with no end runs until the next entry of the same kind starts (the TV works the same way).
            var closed: [ScheduleEntry] = []
            for (i, e) in mine.enumerated() {
                var e = e
                if e.ends == nil, e.source == .oneOff {
                    e = ScheduleEntry(id: e.id, screenId: e.screenId, module: e.module, title: e.title, starts: e.starts,
                                      ends: mine.dropFirst(i + 1).first(where: { $0.module == e.module && $0.starts > e.starts })?.starts, source: e.source)
                }
                closed.append(e)
            }
            out += overlapping(closed, from: from, to: to)
        }
        return out
    }
}
