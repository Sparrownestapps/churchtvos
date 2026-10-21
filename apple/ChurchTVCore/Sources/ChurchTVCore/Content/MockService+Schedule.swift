import Foundation

/// Demo-mode schedules, in memory. The state lives beside the mock service (the actor itself is not changed); it resets when the app restarts.
final class MockScheduleStore: @unchecked Sendable {
    static let shared = MockScheduleStore()
    private let lock = NSLock()
    var dated: [(table: ScheduleTable, row: DatedSchedule)] = []
    var series: [(table: ScheduleTable, row: RepeatingSeries)] = []
    var skipped: [UUID: Set<CalendarDay>] = [:]
    var slots: [SignageSlot] = []
    var groups: [ScreenGroup] = []
    private var seeded = false

    @discardableResult
    func locked<T>(_ body: (MockScheduleStore) -> T) -> T { lock.lock(); defer { lock.unlock() }; seed(); return body(self) }

    func reset() { lock.lock(); seeded = false; dated = []; series = []; skipped = [:]; slots = []; groups = []; lock.unlock() }

    /// A few believable schedules relative to today (lock held).
    private func seed() {
        guard !seeded else { return }
        seeded = true
        let tz = TimeZone.current
        let today = SiteClock.day(of: Date(), in: tz)
        let lastSunday = today.adding(days: -today.weekday)
        func id(_ g: Int, _ n: Int) -> UUID { MockContentStore.uuid(g, n) }
        let auditorium = id(5, 1), kidsWing = id(5, 2), eastside = id(5, 5)
        series = [
            (.deckSeries, RepeatingSeries(id: id(9, 1), locationId: auditorium, name: "Sunday service", days: [0], startTime: ClockTime(9), endTime: ClockTime(12),
                                          startDate: lastSunday.adding(days: -49), itemIds: [MockService.sundayDeck.id], onEnd: .loop)),
            (.kidsSeries, RepeatingSeries(id: id(9, 2), locationId: kidsWing, name: "Sunday Kids rotation", days: [0], startTime: ClockTime(9), endTime: ClockTime(12),
                                          startDate: lastSunday.adding(days: -14), itemIds: [MockService.braveList.id, MockService.gardenList.id], onEnd: .loop)),
        ]
        let christmasDay = CalendarDay(year: today.month == 12 && today.day > 24 ? today.year + 1 : today.year, month: 12, day: 24)
        dated = [
            (.deckSchedules, DatedSchedule(id: id(9, 3), locationId: auditorium, itemId: MockService.christmasDeck.id,
                                           startsAt: SiteClock.instant(day: christmasDay, time: ClockTime(18), in: tz), endsAt: SiteClock.instant(day: christmasDay, time: ClockTime(20), in: tz))),
            (.kidsSchedules, DatedSchedule(id: id(9, 4), locationId: eastside, itemId: MockService.gardenList.id,
                                           startsAt: SiteClock.instant(day: lastSunday.adding(days: 7), time: ClockTime(10, 30), in: tz), endsAt: nil)),
        ]
        groups = [ScreenGroup(id: id(8, 1), name: "Lobby screens"), ScreenGroup(id: id(8, 2), name: "Youth screens")]
        slots = [
            SignageSlot(id: id(9, 5), screenId: MockService.id(3), playlistId: id(7, 1), days: [1, 2, 3, 4, 5, 6], startTime: ClockTime(8), endTime: ClockTime(17), priority: 0),
            SignageSlot(id: id(9, 6), groupId: id(8, 1), playlistId: id(7, 2), days: [0], startTime: ClockTime(8, 30), endTime: ClockTime(12, 30), priority: 1),
        ]
    }
}

extension MockService: ScheduleService {
    private func scheduleDelay() async { try? await Task.sleep(nanoseconds: 120_000_000) }

    public func listScreenGroups(organizationId: UUID) async throws -> [ScreenGroup] {
        await scheduleDelay()
        return MockScheduleStore.shared.locked { $0.groups }
    }

    private func zone(forLocation id: UUID) -> TimeZone {
        let site = store.locations.first { $0.id == id }?.siteId
        return SiteClock.timeZone(id: store.sites.first { $0.id == site }?.timezone)
    }

    public func scheduleSnapshot(module: AppModule, organizationId: UUID, now: Date) async throws -> ScheduleSnapshot {
        await scheduleDelay()
        let st = MockScheduleStore.shared
        if module == .signage { return ScheduleSnapshot(slots: st.locked { $0.slots }) }
        guard let dated = ScheduleTable.dated(module), let seriesTable = ScheduleTable.series(module) else { return .empty }
        let (d, s, skipped) = st.locked { ($0.dated, $0.series, $0.skipped) }
        let series = s.filter { $0.table == seriesTable }.map(\.row)
        var occ: [SeriesOccurrence] = []
        for row in series {
            occ += SeriesExpander.occurrences(of: row, skipped: skipped[row.id] ?? [], from: now, to: now.addingTimeInterval(14 * 86_400), in: zone(forLocation: row.locationId))
        }
        return ScheduleSnapshot(dated: d.filter { $0.table == dated && ($0.row.endsAt ?? .distantFuture) > now }.map(\.row).sorted { $0.startsAt < $1.startsAt },
                                series: series, occurrences: occ.sorted { $0.startsAt < $1.startsAt })
    }

    public func createSchedules(_ rows: [NewScheduleRow], organizationId: UUID) async throws {
        await scheduleDelay()
        func uuid(_ r: NewScheduleRow, _ k: String) -> UUID? { r.values[k]?.stringValue.flatMap(UUID.init(uuidString:)) }
        func ints(_ r: NewScheduleRow) -> [Int] { (r.values["days"]?.arrayValue ?? []).compactMap(\.intValue) }
        let store = MockScheduleStore.shared
        store.locked { st in
            for r in rows {
                switch r.table {
                case .deckSchedules, .kidsSchedules:
                    guard let loc = uuid(r, "location_id"), let item = uuid(r, r.table.itemColumn),
                          let a = r.values["starts_at"]?.stringValue.flatMap(ChurchJSON.parseTimestamp) else { continue }
                    st.dated.append((r.table, DatedSchedule(id: UUID(), locationId: loc, itemId: item, startsAt: a, endsAt: r.values["ends_at"]?.stringValue.flatMap(ChurchJSON.parseTimestamp))))
                case .deckSeries, .kidsSeries:
                    guard let loc = uuid(r, "location_id"), let a = r.values["start_time"]?.stringValue.flatMap({ ClockTime(db: $0) }),
                          let b = r.values["end_time"]?.stringValue.flatMap({ ClockTime(db: $0) }),
                          let sd = r.values["start_date"]?.stringValue.flatMap({ CalendarDay(string: $0) }) else { continue }
                    let ids = (r.values[r.table.rotationColumn]?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
                    st.series.append((r.table, RepeatingSeries(id: UUID(), locationId: loc, name: r.values["name"]?.stringValue, days: ints(r), startTime: a, endTime: b, startDate: sd,
                                                               endDate: r.values["end_date"]?.stringValue.flatMap { CalendarDay(string: $0) }, itemIds: ids,
                                                               onEnd: OnEnd(rawValue: r.values["on_end"]?.stringValue ?? "") ?? .loop)))
                case .signageSlots:
                    guard let pl = uuid(r, "playlist_id"), let a = r.values["start_time"]?.stringValue.flatMap({ ClockTime(db: $0) }),
                          let b = r.values["end_time"]?.stringValue.flatMap({ ClockTime(db: $0) }) else { continue }
                    st.slots.append(SignageSlot(id: UUID(), screenId: uuid(r, "screen_id"), groupId: uuid(r, "group_id"), playlistId: pl, days: ints(r), startTime: a, endTime: b,
                                                endIsEndOfDay: r.values["end_time"]?.stringValue?.hasPrefix("23:59:59") == true, priority: r.values["priority"]?.intValue ?? 0))
                }
            }
        }
    }

    public func deleteSchedule(table: ScheduleTable, id: UUID, organizationId: UUID) async throws {
        await scheduleDelay()
        MockScheduleStore.shared.locked { st in
            st.dated.removeAll { $0.row.id == id }
            st.series.removeAll { $0.row.id == id }
            st.slots.removeAll { $0.id == id }
            st.skipped[id] = nil
        }
    }

    public func skipSeriesDate(table: ScheduleTable, seriesId: UUID, on day: CalendarDay) async throws {
        await scheduleDelay()
        MockScheduleStore.shared.locked { $0.skipped[seriesId, default: []].insert(day) }
    }
}
