import XCTest
@testable import ChurchTVCore

final class SchedulingTests: XCTestCase {
    let toronto = TimeZone(identifier: "America/Toronto")!
    let org = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000001")!
    let deckTarget = ScheduleTarget.deck(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000D1")!, name: "Sunday")
    let kidsTarget = ScheduleTarget.playlist(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000E1")!, name: "Week 3", kind: .kids)
    let locA = UUID(uuidString: "D0D0D0D0-0000-4000-8000-00000000A001")!
    let locB = UUID(uuidString: "D0D0D0D0-0000-4000-8000-00000000A002")!

    func iso(_ d: Date) -> String { ChurchJSON.formatTimestamp(d) }
    func inst(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ tz: TimeZone? = nil) -> Date {
        SiteClock.instant(day: CalendarDay(year: y, month: m, day: d), time: ClockTime(h, min), in: tz ?? toronto)
    }

    // MARK: Time conversion

    func testSundayNineStaysNineAcrossFallBack() {
        // Toronto falls back on Sunday 2026-11-01: 9:00 is 13:00Z before and 14:00Z after.
        XCTAssertEqual(iso(inst(2026, 10, 25, 9)), "2026-10-25T13:00:00.000Z")
        XCTAssertEqual(iso(inst(2026, 11, 1, 9)), "2026-11-01T14:00:00.000Z")
        XCTAssertEqual(iso(inst(2026, 11, 8, 9)), "2026-11-08T14:00:00.000Z")
        for (d, m) in [(25, 10), (1, 11), (8, 11)] {
            let i = inst(2026, m, d, 9)
            XCTAssertEqual(SiteClock.time(of: i, in: toronto), ClockTime(9))
            XCTAssertEqual(SiteClock.day(of: i, in: toronto), CalendarDay(year: 2026, month: m, day: d))
        }
    }

    func testSpringForwardAndAmbiguousTimes() {
        XCTAssertEqual(iso(inst(2026, 3, 8, 9)), "2026-03-08T13:00:00.000Z")           // 9:00 EDT
        XCTAssertEqual(iso(inst(2026, 3, 7, 9)), "2026-03-07T14:00:00.000Z")           // 9:00 EST the day before
        XCTAssertEqual(iso(inst(2026, 3, 8, 2, 30)), "2026-03-08T07:30:00.000Z")       // does not exist: lands an hour later (3:30 EDT)
        XCTAssertEqual(iso(inst(2026, 11, 1, 1, 30)), "2026-11-01T05:30:00.000Z")      // ambiguous: the first one (EDT)
    }

    func testDifferentSiteZoneGivesDifferentInstant() {
        let vancouver = TimeZone(identifier: "America/Vancouver")!
        XCTAssertEqual(iso(inst(2026, 10, 25, 9, 0, vancouver)), "2026-10-25T16:00:00.000Z")
        XCTAssertEqual(SiteClock.timeZone(id: nil).identifier, "America/Toronto")
        XCTAssertEqual(SiteClock.timeZone(id: "Not/AZone").identifier, "America/Toronto")
        XCTAssertTrue(SiteClock.differsFromDevice(vancouver, device: toronto))
        XCTAssertFalse(SiteClock.differsFromDevice(TimeZone(identifier: "America/New_York")!, device: toronto))
    }

    func testCalendarDayAndLabels() {
        let d = CalendarDay(string: "2026-11-01")!
        XCTAssertEqual(d.weekday, 0)                                // Sunday
        XCTAssertEqual(d.adding(days: 30).string, "2026-12-01")
        XCTAssertEqual(CalendarDay(string: "2026-02-28")!.adding(days: 1).string, "2026-03-01")
        XCTAssertNil(CalendarDay(string: "nope"))
        XCTAssertEqual(ClockTime(23, 59).dbString, "23:59:59")
        XCTAssertEqual(ClockTime(db: "08:30:00"), ClockTime(8, 30))
        XCTAssertEqual(ScheduleDays.label([0]), "Sun")
        XCTAssertEqual(ScheduleDays.label([1, 2, 3, 4, 5]), "Mon-Fri")
        XCTAssertEqual(ScheduleDays.label(Array(0...6)), "daily")
        XCTAssertEqual(ScheduleDays.label([0, 6]), "Sun, Sat")
        let wall = SiteClock.wallDate(day: d, time: ClockTime(9, 15))
        XCTAssertEqual(SiteClock.wallParts(wall).time, ClockTime(9, 15))
        XCTAssertEqual(SiteClock.wallParts(wall).day, d)
    }

    func testInitialFormIsNextSunday() {
        let now = inst(2026, 10, 21, 12)                           // a Wednesday
        let f = ScheduleForm.initial(for: deckTarget, now: now, in: toronto)
        XCTAssertEqual(f.day.string, "2026-10-25")
        XCTAssertEqual(f.rotation, [deckTarget.id])
        let onSunday = ScheduleForm.initial(for: deckTarget, now: inst(2026, 10, 25, 7), in: toronto)
        XCTAssertEqual(onSunday.day.string, "2026-11-01")           // like nextSundayAt: never today
    }

    // MARK: Building rows

    func testOneOffRowsForDeckPerLocationWithEnd() throws {
        var f = ScheduleForm.initial(for: deckTarget, now: inst(2026, 10, 21, 12), in: toronto)
        f.locationIds = [locA, locB]
        let vancouver = TimeZone(identifier: "America/Vancouver")!
        let rows = try ScheduleRowBuilder.rows(target: deckTarget, form: f, organizationId: org, orderedLocations: [locA, locB]) { $0 == self.locA ? self.toronto : vancouver }
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.table == .deckSchedules })
        let a = rows[0].values, b = rows[1].values
        XCTAssertEqual(a["location_id"]?.stringValue, locA.uuidString.lowercased())
        XCTAssertEqual(a["deck_id"]?.stringValue, deckTarget.id.uuidString.lowercased())
        XCTAssertEqual(a["organization_id"]?.stringValue, org.uuidString.lowercased())
        XCTAssertEqual(a["starts_at"]?.stringValue, "2026-10-25T13:00:00.000Z")
        XCTAssertEqual(a["ends_at"]?.stringValue, "2026-10-25T16:00:00.000Z")
        XCTAssertEqual(b["starts_at"]?.stringValue, "2026-10-25T16:00:00.000Z")   // 9:00 in Vancouver
        XCTAssertNil(a["playlist_id"])
    }

    func testOneOffKidsNoEnd() throws {
        var f = ScheduleForm.initial(for: kidsTarget, now: inst(2026, 10, 21, 12), in: toronto)
        f.locationIds = [locA]; f.hasEnd = false
        let rows = try ScheduleRowBuilder.rows(target: kidsTarget, form: f, organizationId: org, orderedLocations: [locA]) { _ in self.toronto }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].table, .kidsSchedules)
        XCTAssertNil(rows[0].values["ends_at"])
        XCTAssertEqual(rows[0].values["playlist_id"]?.stringValue, kidsTarget.id.uuidString.lowercased())
    }

    func testSeriesRowsDeckAndKidsRotation() throws {
        let second = UUID()
        var f = ScheduleForm.initial(for: kidsTarget, now: inst(2026, 10, 21, 12), in: toronto)
        f.mode = .repeating; f.locationIds = [locA, locB]; f.weekdays = [0, 3]
        f.rotation = [kidsTarget.id, second]; f.onEnd = .stop; f.name = "  Fall rotation "; f.hasEndDate = true
        let rows = try ScheduleRowBuilder.rows(target: kidsTarget, form: f, organizationId: org, orderedLocations: [locA, locB]) { _ in self.toronto }
        XCTAssertEqual(rows.count, 2)
        let v = rows[0].values
        XCTAssertEqual(rows[0].table, .kidsSeries)
        XCTAssertEqual(v["days"], .array([.number(0), .number(3)]))
        XCTAssertEqual(v["start_time"]?.stringValue, "09:00")
        XCTAssertEqual(v["end_time"]?.stringValue, "12:00")
        XCTAssertEqual(v["start_date"]?.stringValue, "2026-10-25")
        XCTAssertEqual(v["end_date"]?.stringValue, "2027-01-17")
        XCTAssertEqual(v["playlist_ids"]?.arrayValue?.compactMap(\.stringValue), [kidsTarget.id, second].map { $0.uuidString.lowercased() })
        XCTAssertEqual(v["on_end"]?.stringValue, "stop")
        XCTAssertEqual(v["name"]?.stringValue, "Fall rotation")
        // JSON the server receives
        let json = try String(data: JSONEncoder().encode(RawJSON.object(v)), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"days\":[0,3]"))

        var d = f; d.rotation = [deckTarget.id]; d.hasEndDate = false; d.name = ""
        let deckRows = try ScheduleRowBuilder.rows(target: deckTarget, form: d, organizationId: org, orderedLocations: [locA]) { _ in self.toronto }
        XCTAssertEqual(deckRows[0].table, .deckSeries)
        XCTAssertEqual(deckRows[0].values["deck_ids"]?.arrayValue?.count, 1)
        XCTAssertNil(deckRows[0].values["end_date"]); XCTAssertNil(deckRows[0].values["name"])
    }

    func testValidation() {
        var f = ScheduleForm.initial(for: deckTarget, in: toronto)
        XCTAssertEqual(f.problem, "Choose at least one location.")
        f.locationIds = [locA]
        XCTAssertNil(f.problem)
        f.end = ClockTime(8); XCTAssertEqual(f.problem, "The end time must be after the start time.")
        f.hasEnd = false; XCTAssertNil(f.problem)
        f.mode = .repeating; XCTAssertEqual(f.problem, "The end time must be after the start time.")   // repeating always has an end
        f.end = ClockTime(12); f.weekdays = []; XCTAssertEqual(f.problem, "Choose at least one day.")
        f.weekdays = [0]; f.hasEndDate = true; f.endDate = f.startDate.adding(days: -1)
        XCTAssertEqual(f.problem, "The end date must not be before the start date.")
        XCTAssertThrowsError(try ScheduleRowBuilder.rows(target: deckTarget, form: f, organizationId: org, orderedLocations: [locA]) { _ in self.toronto })
    }

    // MARK: Signage

    func testSignagePriorityAndRows() throws {
        let screen = UUID(), group = UUID(), pl = UUID()
        let existing = [
            SignageSlot(id: UUID(), screenId: screen, playlistId: UUID(), days: [1], startTime: ClockTime(8), endTime: ClockTime(9), priority: 2),
            SignageSlot(id: UUID(), screenId: screen, playlistId: UUID(), days: [1], startTime: ClockTime(8), endTime: ClockTime(9), priority: 0),
            SignageSlot(id: UUID(), groupId: group, playlistId: UUID(), days: [1], startTime: ClockTime(8), endTime: ClockTime(9), priority: 7),
        ]
        XCTAssertEqual(SignagePriority.value(existing: existing, for: .screen(screen), higher: false), 0)
        XCTAssertEqual(SignagePriority.value(existing: existing, for: .screen(screen), higher: true), 3)
        XCTAssertEqual(SignagePriority.value(existing: existing, for: .group(group), higher: true), 8)
        XCTAssertEqual(SignagePriority.value(existing: existing, for: .screen(UUID()), higher: true), 1)

        var f = SignageForm()
        XCTAssertEqual(f.problem, "Choose a screen or a group.")
        f.targets = [.screen(screen), .group(group)]; f.weekdays = [0, 6]; f.higherPriority = true
        XCTAssertNil(f.problem)
        let rows = try ScheduleRowBuilder.slotRows(playlistId: pl, form: f, organizationId: org, existing: existing)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].table, .signageSlots)
        XCTAssertEqual(rows[0].values["screen_id"]?.stringValue, screen.uuidString.lowercased())
        XCTAssertNil(rows[0].values["group_id"])                      // screen XOR group
        XCTAssertEqual(rows[1].values["group_id"]?.stringValue, group.uuidString.lowercased())
        XCTAssertNil(rows[1].values["screen_id"])
        XCTAssertEqual(rows[0].values["end_time"]?.stringValue, "23:59:59")
        XCTAssertEqual(rows[0].values["start_time"]?.stringValue, "00:00")
        XCTAssertEqual(rows[0].values["priority"]?.intValue, 3)
        XCTAssertEqual(rows[1].values["priority"]?.intValue, 8)
        f.end = ClockTime(0); XCTAssertEqual(f.problem, "The end time must be after the start time.")
    }

    // MARK: Series expansion

    func testRotationLoopStopAndSkip() {
        let a = UUID(), b = UUID()
        let start = CalendarDay(year: 2026, month: 10, day: 25)       // a Sunday
        var s = RepeatingSeries(id: UUID(), locationId: locA, days: [0], startTime: ClockTime(9), endTime: ClockTime(12), startDate: start, itemIds: [a, b], onEnd: .loop)
        let from = inst(2026, 10, 25, 0), to = inst(2026, 12, 1, 0)
        var occ = SeriesExpander.occurrences(of: s, from: from, to: to, in: toronto)
        XCTAssertEqual(occ.map(\.onDate.string), ["2026-10-25", "2026-11-01", "2026-11-08", "2026-11-15", "2026-11-22", "2026-11-29"])
        XCTAssertEqual(occ.map(\.itemId), [a, b, a, b, a, b])
        // Wall-clock times hold across the clock change.
        XCTAssertEqual(occ.map { SiteClock.time(of: $0.startsAt, in: toronto) }, Array(repeating: ClockTime(9), count: 6))
        XCTAssertEqual(iso(occ[1].startsAt), "2026-11-01T14:00:00.000Z")
        // Skip: the rotation waits, so the skipped item moves to the next date.
        occ = SeriesExpander.occurrences(of: s, skipped: [CalendarDay(year: 2026, month: 11, day: 1)], from: from, to: to, in: toronto)
        XCTAssertEqual(occ.map(\.onDate.string), ["2026-10-25", "2026-11-08", "2026-11-15", "2026-11-22", "2026-11-29"])
        XCTAssertEqual(occ.map(\.itemId), [a, b, a, b, a])
        // Stop: ends after the last item.
        s.onEnd = .stop
        occ = SeriesExpander.occurrences(of: s, from: from, to: to, in: toronto)
        XCTAssertEqual(occ.map(\.itemId), [a, b])
        // End date and two days per week.
        s.onEnd = .loop; s.days = [0, 3]; s.endDate = CalendarDay(year: 2026, month: 11, day: 4)
        occ = SeriesExpander.occurrences(of: s, from: from, to: to, in: toronto)
        XCTAssertEqual(occ.map(\.onDate.string), ["2026-10-25", "2026-10-28", "2026-11-01", "2026-11-04"])
    }

    // MARK: Overlap

    func testOverlapHints() {
        let other = UUID()
        let existingOneOff = DatedSchedule(id: UUID(), locationId: locA, itemId: other, startsAt: inst(2026, 10, 25, 10), endsAt: inst(2026, 10, 25, 11))
        let series = RepeatingSeries(id: UUID(), locationId: locA, name: "Sunday rotation", days: [0], startTime: ClockTime(9), endTime: ClockTime(12),
                                     startDate: CalendarDay(year: 2026, month: 10, day: 4), itemIds: [other])
        let snap = ScheduleSnapshot(dated: [existingOneOff], series: [series])
        func hints(_ f: ScheduleForm) -> [String] {
            ScheduleOverlap.hints(target: deckTarget, form: f, snapshot: snap, itemName: { _ in "Other" }, locationName: { _ in "Auditorium" }, timeZone: { _ in self.toronto }, orderedLocations: [locA, locB])
        }
        var f = ScheduleForm.initial(for: deckTarget, now: inst(2026, 10, 21, 12), in: toronto)
        f.locationIds = [locA]
        let once = hints(f)                                          // Sun 9-12 collides with the one-off and the repeat
        XCTAssertEqual(once.count, 2)
        XCTAssertTrue(once[0].contains("already scheduled")); XCTAssertTrue(once[1].contains("replaces the repeating"))
        f.locationIds = [locB]; XCTAssertTrue(hints(f).isEmpty)       // other location: nothing
        f.locationIds = [locA]; f.day = CalendarDay(year: 2026, month: 10, day: 26); XCTAssertTrue(hints(f).isEmpty)  // Monday
        f.day = CalendarDay(year: 2026, month: 10, day: 25); f.start = ClockTime(13); f.end = ClockTime(14); XCTAssertTrue(hints(f).isEmpty)

        var r = ScheduleForm.initial(for: deckTarget, now: inst(2026, 10, 21, 12), in: toronto)
        r.mode = .repeating; r.locationIds = [locA]
        let rep = hints(r)                                           // overlaps the series and replaced by the one-off on Oct 25
        XCTAssertEqual(rep.count, 2)
        XCTAssertTrue(rep.contains { $0.contains("overlaps") }); XCTAssertTrue(rep.contains { $0.contains("replaces this repeat") })
        r.weekdays = [3]; XCTAssertTrue(hints(r).isEmpty)
        r.weekdays = [0]; r.hasEndDate = true; r.endDate = CalendarDay(year: 2026, month: 10, day: 3); r.startDate = CalendarDay(year: 2026, month: 9, day: 1)
        XCTAssertTrue(hints(r).isEmpty)                              // finished before the series starts

        let slot = SignageSlot(id: UUID(), screenId: UUID(), playlistId: other, days: [1, 2], startTime: ClockTime(8), endTime: ClockTime(17), priority: 1)
        var sf = SignageForm(); sf.targets = [slot.target]; sf.weekdays = [2]; sf.start = ClockTime(16); sf.end = ClockTime(18)
        XCTAssertEqual(ScheduleOverlap.signageHints(form: sf, existing: [slot], itemName: { _ in "Lobby" }, targetName: { _ in "TV" }).count, 1)
        sf.start = ClockTime(17); XCTAssertTrue(ScheduleOverlap.signageHints(form: sf, existing: [slot], itemName: { _ in "Lobby" }, targetName: { _ in "TV" }).isEmpty)
        sf.start = ClockTime(9); sf.weekdays = [3]; XCTAssertTrue(ScheduleOverlap.signageHints(form: sf, existing: [slot], itemName: { _ in "Lobby" }, targetName: { _ in "TV" }).isEmpty)
    }

    // MARK: Mock service (demo mode)

    func testMockServiceSchedulingRoundTrip() async throws {
        MockScheduleStore.shared.reset()
        let svc = MockService()
        let snap = try await svc.scheduleSnapshot(module: .slides, organizationId: org, now: Date())
        XCTAssertFalse(snap.series.isEmpty)
        XCTAssertFalse(snap.occurrences.isEmpty)
        var f = ScheduleForm.initial(for: deckTarget, in: toronto)
        f.locationIds = [MockContentStore.uuid(5, 1)]
        let rows = try ScheduleRowBuilder.rows(target: deckTarget, form: f, organizationId: org, orderedLocations: [MockContentStore.uuid(5, 1)]) { _ in self.toronto }
        try await svc.createSchedules(rows, organizationId: org)
        let after = try await svc.scheduleSnapshot(module: .slides, organizationId: org, now: Date())
        XCTAssertEqual(after.dated.count, snap.dated.count + 1)
        let series = try XCTUnwrap(after.series.first)
        let first = try XCTUnwrap(after.occurrences.first { $0.seriesId == series.id })
        try await svc.skipSeriesDate(table: .deckSeries, seriesId: series.id, on: first.onDate)
        let skipped = try await svc.scheduleSnapshot(module: .slides, organizationId: org, now: Date())
        XCTAssertFalse(skipped.occurrences.contains { $0.id == first.id })
        try await svc.deleteSchedule(table: .deckSeries, id: series.id, organizationId: org)
        let gone = try await svc.scheduleSnapshot(module: .slides, organizationId: org, now: Date())
        XCTAssertFalse(gone.series.contains { $0.id == series.id })
        let groups = try await svc.listScreenGroups(organizationId: org)
        XCTAssertFalse(groups.isEmpty)
        MockScheduleStore.shared.reset()
    }
}
