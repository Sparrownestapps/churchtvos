import XCTest
@testable import ChurchTVCore

final class CalendarTests: XCTestCase {
    let toronto = TimeZone(identifier: "America/Toronto")!
    let org = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000001")!
    let locA = UUID(uuidString: "D0D0D0D0-0000-4000-8000-00000000A001")!
    let locB = UUID(uuidString: "D0D0D0D0-0000-4000-8000-00000000A002")!
    let siteA = UUID(uuidString: "D0D0D0D0-0000-4000-8000-00000000B001")!
    let item1 = UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000E1")!
    let item2 = UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000E2")!
    let screen1 = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000101")!
    let fixedId = UUID(uuidString: "D0D0D0D0-0000-4000-8000-00000000FFFF")!

    func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }
    func inst(_ d: CalendarDay, _ h: Int, _ m: Int = 0) -> Date { SiteClock.instant(day: d, time: ClockTime(h, m), in: toronto) }
    func wall(_ d: CalendarDay, _ h: Int, _ m: Int = 0) -> WallTime { WallTime(day: d, minutes: h * 60 + m) }

    // MARK: DST and wall time

    func testSundayNineIsMinute540OnBothSidesOfFallBack() {
        for d in [day(2026, 10, 25), day(2026, 11, 1), day(2026, 11, 8)] {
            let w = WallTime(inst(d, 9), in: toronto)
            XCTAssertEqual(w, wall(d, 9))
        }
        // Real instants differ by an hour across the change.
        XCTAssertEqual(inst(day(2026, 11, 1), 9).timeIntervalSince(inst(day(2026, 10, 25), 9)), 7 * 86_400 + 3600)
    }

    func testEventAcrossTheRepeatedHourKeepsWallMinutes() {
        // Fall back, Sunday 2026-11-01: 00:30 to 03:00 wall is 3.5 real hours but one block from minute 30 to 180.
        let d = day(2026, 11, 1)
        let segs = CalendarSegments.split(eventId: "e", start: inst(d, 0, 30), end: inst(d, 3), in: toronto)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].startMinute, 30); XCTAssertEqual(segs[0].endMinute, 180)
        XCTAssertEqual(inst(d, 3).timeIntervalSince(inst(d, 0, 30)), 3.5 * 3600)
    }

    func testSpringForwardNonexistentTimeLandsLater() {
        let d = day(2026, 3, 8)   // 02:00 -> 03:00
        let w = WallTime(inst(d, 2, 30), in: toronto)
        XCTAssertEqual(w.minutes, 3 * 60 + 30)
        XCTAssertEqual(wall(d, 9).instant(in: toronto), inst(d, 9))
    }

    func testEventPastMidnightSplitsAcrossDays() {
        let d = day(2026, 10, 24)
        let segs = CalendarSegments.split(eventId: "e", start: inst(d, 22), end: inst(d.adding(days: 1), 2), in: toronto)
        XCTAssertEqual(segs.map(\.day), [d, d.adding(days: 1)])
        XCTAssertEqual(segs[0].startMinute, 22 * 60); XCTAssertEqual(segs[0].endMinute, 1440); XCTAssertTrue(segs[0].continuesAfter)
        XCTAssertEqual(segs[1].startMinute, 0); XCTAssertEqual(segs[1].endMinute, 120); XCTAssertTrue(segs[1].continuesBefore)
    }

    func testEventEndingAtMidnightStaysOnItsDay() {
        let d = day(2026, 10, 24)
        let segs = CalendarSegments.split(eventId: "e", start: inst(d, 20), end: inst(d.adding(days: 1), 0), in: toronto)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].endMinute, 1440)
    }

    func testWallTimeNormalizesAndMeasures() {
        let d = day(2026, 10, 24)
        XCTAssertEqual(WallTime(day: d, minutes: 1440).normalized, WallTime(day: d.adding(days: 1), minutes: 0))
        XCTAssertEqual(WallTime(day: d, minutes: -15).normalized, WallTime(day: d.adding(days: -1), minutes: 1425))
        XCTAssertEqual(wall(d.adding(days: 1), 1).minutes(since: wall(d, 23)), 120)
        XCTAssertEqual(day(2026, 10, 21).mondayOfWeek, day(2026, 10, 19))
        XCTAssertEqual(day(2026, 10, 25).mondayOfWeek, day(2026, 10, 19))
        XCTAssertEqual(day(2026, 10, 19).mondayOfWeek, day(2026, 10, 19))
    }

    // MARK: Fixtures

    var directory: CalendarDirectory {
        let loc1 = Location(id: locA, name: "Auditorium", siteId: siteA, modules: ["slides", "kids"])
        let loc2 = Location(id: locB, name: "Gym", siteId: siteA, modules: ["kids"])
        let screen = ScreenInfo(screen: Screen(id: screen1, locationId: locA, name: "Main", groupId: nil, appVersion: "1.5.1"), locationName: "Auditorium", timeZoneId: "America/Toronto")
        return CalendarDirectory(screens: [screen], groups: [], locations: [loc1, loc2], sites: [Site(id: siteA, name: "Downtown", timezone: "America/Toronto")])
    }
    func editor(_ modules: [AppModule] = AppModule.allCases) -> CalendarPermissions { CalendarPermissions(role: .editor, modules: modules, siteIds: nil) }
    func admin() -> CalendarPermissions { CalendarPermissions(role: .admin, modules: AppModule.allCases, siteIds: nil) }

    func oneOffEvent(open: Bool = false, editable: Bool = true) -> CalendarEvent {
        let d = day(2026, 10, 21)
        let s = DatedSchedule(id: fixedId, locationId: locA, itemId: item1, startsAt: inst(d, 10), endsAt: open ? nil : inst(d, 11))
        return CalendarEvent(id: "x", source: .oneOff(module: .kids, table: .kidsSchedules, schedule: s, openEnded: open), style: .kidsOneTime, title: "T",
                             subtitle: nil, start: s.startsAt, end: open ? inst(d, 11) : s.endsAt!, locationId: locA, editable: editable, lockReason: editable ? nil : "locked")
    }

    // MARK: Move and resize rows

    func testMoveOneOffUpdatesStartAndEnd() {
        let d = day(2026, 10, 21)
        let plan = CalendarEditPlanner.plan(event: oneOffEvent(), newStart: wall(d.adding(days: 1), 10, 15), newEnd: wall(d.adding(days: 1), 11, 15), in: toronto, organizationId: org)
        XCTAssertEqual(plan, .apply(.dated(table: .kidsSchedules, id: fixedId, startsAt: inst(d.adding(days: 1), 10, 15), endsAt: inst(d.adding(days: 1), 11, 15))))
    }

    func testResizeOneOffKeepsStart() {
        let d = day(2026, 10, 21)
        let plan = CalendarEditPlanner.plan(event: oneOffEvent(), newStart: wall(d, 10), newEnd: wall(d, 12, 30), in: toronto, organizationId: org)
        XCTAssertEqual(plan, .apply(.dated(table: .kidsSchedules, id: fixedId, startsAt: inst(d, 10), endsAt: inst(d, 12, 30))))
    }

    func testOpenEndedOneOffStaysOpenWhenMoved() {
        let d = day(2026, 10, 21)
        let plan = CalendarEditPlanner.plan(event: oneOffEvent(open: true), newStart: wall(d, 9), newEnd: wall(d, 10), in: toronto, organizationId: org)
        XCTAssertEqual(plan, .apply(.dated(table: .kidsSchedules, id: fixedId, startsAt: inst(d, 9), endsAt: nil)))
        XCTAssertFalse(oneOffEvent(open: true).canResize)
    }

    func testMoveToSamePlaceIsUnchangedAndLockedIsRejected() {
        let d = day(2026, 10, 21)
        XCTAssertEqual(CalendarEditPlanner.plan(event: oneOffEvent(), newStart: wall(d, 10), newEnd: wall(d, 11), in: toronto, organizationId: org), .unchanged)
        XCTAssertEqual(CalendarEditPlanner.plan(event: oneOffEvent(editable: false), newStart: wall(d, 9), newEnd: wall(d, 10), in: toronto, organizationId: org), .rejected("locked"))
    }

    func testMoveAcrossDSTChangeKeepsWallClock() {
        // A one-off Saturday 9:00 moved to Sunday 9:00 after the fall-back keeps 9:00 on the clock (instant is 25 hours later).
        let sat = day(2026, 10, 31)
        let s = DatedSchedule(id: fixedId, locationId: locA, itemId: item1, startsAt: inst(sat, 9), endsAt: inst(sat, 10))
        let e = CalendarEvent(id: "x", source: .oneOff(module: .kids, table: .kidsSchedules, schedule: s, openEnded: false), style: .kidsOneTime, title: "T", subtitle: nil, start: s.startsAt, end: s.endsAt!, locationId: locA, editable: true, lockReason: nil)
        guard case .apply(.dated(_, _, let a, _)) = CalendarEditPlanner.plan(event: e, newStart: wall(sat.adding(days: 1), 9), newEnd: wall(sat.adding(days: 1), 10), in: toronto, organizationId: org) else { return XCTFail() }
        XCTAssertEqual(a.timeIntervalSince(s.startsAt), 25 * 3600)
        XCTAssertEqual(SiteClock.time(of: a, in: toronto), ClockTime(9))
    }

    func seriesEvent(items: [UUID]) -> CalendarEvent {
        let sun = day(2026, 10, 25)
        let series = RepeatingSeries(id: fixedId, locationId: locA, name: "Sunday", days: [0], startTime: ClockTime(9), endTime: ClockTime(12), startDate: day(2026, 9, 6), endDate: nil, itemIds: items)
        let occ = SeriesOccurrence(seriesId: series.id, locationId: locA, onDate: sun, startsAt: inst(sun, 9), endsAt: inst(sun, 12), itemId: items[0], occurrenceNo: 8)
        return CalendarEvent(id: "s", source: .occurrence(module: .kids, table: .kidsSeries, series: series, occurrence: occ), style: .kidsRepeating, title: "S", subtitle: nil,
                             start: occ.startsAt, end: occ.endsAt, locationId: locA, editable: true, lockReason: nil)
    }

    func testSeriesMoveOffersThisDateOnlyAndWholeSeries() throws {
        let sun = day(2026, 10, 25)
        let plan = CalendarEditPlanner.plan(event: seriesEvent(items: [item1, item2]), newStart: wall(sun, 10), newEnd: wall(sun, 13), in: toronto, organizationId: org, newId: { self.fixedId })
        guard case .choose(_, _, let choices) = plan else { return XCTFail("expected a choice") }
        XCTAssertEqual(choices.map(\.label), ["This date only", "Whole series"])
        // This date only: skip that date + a one-off at the new time, same item and room, with a client id for undo.
        guard case .thisDateOnly(let table, let sid, let skipDay, let oneOffId, let row) = choices[0].change else { return XCTFail() }
        XCTAssertEqual(table, .kidsSeries); XCTAssertEqual(sid, fixedId); XCTAssertEqual(skipDay, sun); XCTAssertEqual(oneOffId, fixedId)
        XCTAssertEqual(row.table, .kidsSchedules)
        XCTAssertEqual(row.values["playlist_id"]?.stringValue, item1.uuidString.lowercased())
        XCTAssertEqual(row.values["location_id"]?.stringValue, locA.uuidString.lowercased())
        XCTAssertEqual(row.values["starts_at"]?.stringValue, ChurchJSON.formatTimestamp(inst(sun, 10)))
        XCTAssertEqual(row.values["ends_at"]?.stringValue, ChurchJSON.formatTimestamp(inst(sun, 13)))
        XCTAssertEqual(row.values["id"]?.stringValue, fixedId.uuidString.lowercased())
        XCTAssertTrue(choices[0].hint?.contains("rotation waits") == true)
        // Whole series: new times, same day, dates unchanged.
        guard case .update(.kidsSeries, _, let v) = choices[1].change else { return XCTFail() }
        XCTAssertEqual(v["start_time"]?.stringValue, "10:00"); XCTAssertEqual(v["end_time"]?.stringValue, "13:00")
        XCTAssertEqual(v["days"], .array([.number(0)])); XCTAssertEqual(v["start_date"]?.stringValue, "2026-09-06"); XCTAssertEqual(v["end_date"], RawJSON.null)
    }

    func testSeriesMovedToAnotherWeekdayShiftsDaysAndDates() throws {
        let mon = day(2026, 10, 26)
        guard case .choose(_, _, let choices) = CalendarEditPlanner.plan(event: seriesEvent(items: [item1]), newStart: wall(mon, 9), newEnd: wall(mon, 12), in: toronto, organizationId: org) else { return XCTFail() }
        guard case .update(_, _, let v) = choices.last!.change else { return XCTFail() }
        XCTAssertEqual(v["days"], .array([.number(1)]))
        XCTAssertEqual(v["start_date"]?.stringValue, "2026-09-07")
        XCTAssertFalse(choices[0].hint?.contains("rotation") == true)   // single item: no rotation warning
    }

    func slotEvent(days: [Int]) -> CalendarEvent {
        let d = day(2026, 10, 21)   // Wednesday
        let slot = SignageSlot(id: fixedId, screenId: screen1, playlistId: item1, days: days, startTime: ClockTime(8), endTime: ClockTime(17), priority: 2)
        return CalendarEvent(id: "slot", source: .slot(slot), style: .signage, title: "Slot", subtitle: nil, start: inst(d, 8), end: inst(d, 17), locationId: nil, editable: true, lockReason: nil)
    }

    func testSingleDaySlotUpdatesDaysAndTimes() {
        let d = day(2026, 10, 22)   // moved to Thursday
        XCTAssertEqual(CalendarEditPlanner.plan(event: slotEvent(days: [3]), newStart: wall(d, 9), newEnd: wall(d, 18), in: toronto, organizationId: org),
                       .apply(.update(table: .signageSlots, id: fixedId, values: ["days": .array([.number(4)]), "start_time": .string("09:00"), "end_time": .string("18:00")])))
    }

    func testMultiDaySlotAsksAndSplitsOneDay() {
        let d = day(2026, 10, 22)
        guard case .choose(_, _, let choices) = CalendarEditPlanner.plan(event: slotEvent(days: [1, 3, 5]), newStart: wall(d, 8), newEnd: wall(d, 17), in: toronto, organizationId: org) else { return XCTFail() }
        guard case .update(_, _, let all) = choices[0].change else { return XCTFail() }
        XCTAssertEqual(all["days"], .array([.number(2), .number(4), .number(6)]))      // every day shifted by one
        guard case .splitRule(.signageSlots, let id, let remaining, let copy) = choices[1].change else { return XCTFail() }
        XCTAssertEqual(id, fixedId); XCTAssertEqual(remaining, [1, 5])
        XCTAssertEqual(copy["days"], .array([.number(4)]))
        XCTAssertEqual(copy["playlist_id"]?.stringValue, item1.uuidString.lowercased())
        XCTAssertEqual(copy["screen_id"]?.stringValue, screen1.uuidString.lowercased())
        XCTAssertEqual(copy["priority"], .number(2))
        XCTAssertNil(copy["id"])
    }

    func testRuleEndingAtMidnightStoresEndOfDayAndPastMidnightIsRejected() {
        let d = day(2026, 10, 21)
        guard case .apply(.update(_, _, let v)) = CalendarEditPlanner.plan(event: slotEvent(days: [3]), newStart: wall(d, 20), newEnd: WallTime(day: d, minutes: 1440), in: toronto, organizationId: org) else { return XCTFail() }
        XCTAssertEqual(v["end_time"]?.stringValue, "23:59:59")
        XCTAssertEqual(CalendarEditPlanner.plan(event: slotEvent(days: [3]), newStart: wall(d, 23), newEnd: wall(d.adding(days: 1), 1), in: toronto, organizationId: org), .rejected(CalendarEditPlanner.pastMidnight))
    }

    // MARK: Building events

    func testBuilderProducesBlocksForEveryModuleWithLabelsAndPermissions() {
        let mon = day(2026, 10, 19)
        let days = (0..<7).map { mon.adding(days: $0) }
        let series = RepeatingSeries(id: fixedId, locationId: locA, name: "Sunday rotation", days: [0], startTime: ClockTime(9), endTime: ClockTime(12), startDate: day(2026, 9, 6), itemIds: [item1, item2])
        let sun = day(2026, 10, 25)
        let occ = SeriesOccurrence(seriesId: fixedId, locationId: locA, onDate: sun, startsAt: inst(sun, 9), endsAt: inst(sun, 12), itemId: item2, occurrenceNo: 7)
        let one = DatedSchedule(id: UUID(), locationId: locA, itemId: item1, startsAt: inst(day(2026, 10, 21), 16), endsAt: nil)
        let next = DatedSchedule(id: UUID(), locationId: locA, itemId: item2, startsAt: inst(day(2026, 10, 21), 17, 30), endsAt: inst(day(2026, 10, 21), 18))
        let slot = SignageSlot(id: UUID(), screenId: screen1, playlistId: item1, days: [1, 2], startTime: ClockTime(8), endTime: ClockTime(23, 59), endIsEndOfDay: true)
        let rule = ModuleRule(id: UUID(), screenId: screen1, module: "off", days: [0], startTime: ClockTime(0), endTime: ClockTime(7))
        let data = CalendarData(snapshots: [.kids: ScheduleSnapshot(dated: [one, next], series: [series], occurrences: [occ]), .signage: ScheduleSnapshot(slots: [slot])],
                                moduleRules: [rule], names: [item1: "Brave", item2: "Garden"])
        let lane = directory.resolve(.all)
        let ev = CalendarEventBuilder.events(data: data, directory: directory, permissions: editor(), lane: lane, days: days)
        XCTAssertEqual(ev.filter { $0.style == .signage }.count, 2)                       // Mon and Tue
        XCTAssertEqual(ev.filter { $0.style == .moduleSwitch }.count, 1)
        let rep = ev.first { $0.style == .kidsRepeating }
        XCTAssertEqual(rep?.title, "Week 7: Garden"); XCTAssertEqual(rep?.subtitle, "Sunday rotation")
        let open = ev.first { $0.id.hasPrefix("kids-one:\(one.id)") }
        XCTAssertEqual(open?.end, next.startsAt)                                          // open-ended runs until the next one in the room
        XCTAssertEqual(ev.first { $0.style == .moduleSwitch }?.editable, false)           // editors may not change module switches
        XCTAssertEqual(ev.first { $0.style == .signage }?.editable, true)
        XCTAssertEqual(ev.first { $0.style == .signage }?.end, SiteClock.instant(day: day(2026, 10, 20), time: ClockTime(0), in: toronto))   // 23:59:59 = midnight
        XCTAssertTrue(CalendarEventBuilder.events(data: data, directory: directory, permissions: admin(), lane: lane, days: days).filter { $0.style == .moduleSwitch }.allSatisfy(\.editable))
        // An operator-like member cannot edit anything.
        let ro = CalendarPermissions(role: .operator, modules: AppModule.allCases)
        XCTAssertTrue(CalendarEventBuilder.events(data: data, directory: directory, permissions: ro, lane: lane, days: days).allSatisfy { !$0.editable })
    }

    func testLaneFilterByLocationAndEventsOutsideTheRangeAreDropped() {
        let d = day(2026, 10, 21)
        let a = DatedSchedule(id: UUID(), locationId: locA, itemId: item1, startsAt: inst(d, 9), endsAt: inst(d, 10))
        let b = DatedSchedule(id: UUID(), locationId: locB, itemId: item1, startsAt: inst(d, 9), endsAt: inst(d, 10))
        let late = DatedSchedule(id: UUID(), locationId: locA, itemId: item1, startsAt: inst(d.adding(days: 9), 9), endsAt: inst(d.adding(days: 9), 10))
        let data = CalendarData(snapshots: [.kids: ScheduleSnapshot(dated: [a, b, late])], names: [item1: "X"])
        let lane = directory.resolve(.location(locA))
        let ev = CalendarEventBuilder.events(data: data, directory: directory, permissions: editor(), lane: lane, days: [d])
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev[0].locationId, locA)
        XCTAssertEqual(CalendarEventBuilder.events(data: data, directory: directory, permissions: editor(), lane: directory.resolve(.all), days: [d]).count, 2)
    }

    func testSiteScopeLocksOtherSites() {
        let d = day(2026, 10, 21)
        let a = DatedSchedule(id: UUID(), locationId: locA, itemId: item1, startsAt: inst(d, 9), endsAt: inst(d, 10))
        let data = CalendarData(snapshots: [.kids: ScheduleSnapshot(dated: [a])], names: [:])
        let scoped = CalendarPermissions(role: .editor, modules: [.kids], siteIds: [UUID()])
        let ev = CalendarEventBuilder.events(data: data, directory: directory, permissions: scoped, lane: directory.resolve(.all), days: [d])
        XCTAssertEqual(ev.first?.editable, false)
        XCTAssertNotNil(ev.first?.lockReason)
    }

    func testWeeklySlotKeepsNineOClockAcrossDST() {
        let sunBefore = day(2026, 10, 25), sunDST = day(2026, 11, 1)
        let slot = SignageSlot(id: UUID(), screenId: screen1, playlistId: item1, days: [0], startTime: ClockTime(9), endTime: ClockTime(12))
        let data = CalendarData(snapshots: [.signage: ScheduleSnapshot(slots: [slot])], names: [:])
        let ev = CalendarEventBuilder.events(data: data, directory: directory, permissions: editor(), lane: directory.resolve(.all), days: [sunBefore, sunDST])
        XCTAssertEqual(ev.count, 2)
        XCTAssertEqual(ev.map { WallTime($0.start, in: toronto).minutes }, [540, 540])
        XCTAssertEqual(ev[1].start.timeIntervalSince(ev[0].start), 7 * 86_400 + 3600)
    }

    func testTimeZoneOfLaneAndMixedZones() {
        let van = Site(id: UUID(), name: "Van", timezone: "America/Vancouver")
        var dir = directory
        dir.sites.append(van)
        dir.locations.append(Location(id: UUID(), name: "West", siteId: van.id, modules: ["kids"]))
        let all = dir.resolve(.all)
        XCTAssertTrue(all.mixedTimeZones)
        XCTAssertEqual(all.timeZone.identifier, "America/Toronto")
        XCTAssertFalse(dir.resolve(.location(locA)).mixedTimeZones)
        XCTAssertEqual(dir.resolve(.screen(screen1)).locationIds, [locA])
    }

    func testBandsFollowRulesAndFallBackToDefault() {
        let rule = ModuleRule(id: UUID(), screenId: screen1, module: "kids", days: [0], startTime: ClockTime(9), endTime: ClockTime(12))
        let lane = directory.resolve(.screen(screen1))
        let bands = CalendarBands.bands(rules: [rule], lane: lane, defaultModule: "signage", days: [day(2026, 10, 25), day(2026, 10, 26)])
        XCTAssertEqual(bands.filter { $0.day == day(2026, 10, 25) }.map { [$0.module, "\($0.fromMinute)", "\($0.toMinute)"] },
                       [["signage", "0", "540"], ["kids", "540", "720"], ["signage", "720", "1440"]])
        XCTAssertEqual(bands.filter { $0.day == day(2026, 10, 26) }.count, 1)
        XCTAssertTrue(CalendarBands.bands(rules: [rule], lane: directory.resolve(.all), defaultModule: "signage", days: [day(2026, 10, 25)]).isEmpty)
    }

    func testPermissionsCanCreate() {
        XCTAssertTrue(editor().canCreate(locations: directory.locations))
        XCTAssertFalse(CalendarPermissions(role: .operator, modules: AppModule.allCases).canCreate(locations: directory.locations))
        XCTAssertTrue(CalendarPermissions(role: .editor, modules: [.signage]).canCreate(locations: directory.locations))
        XCTAssertFalse(CalendarPermissions(role: .editor, modules: [.kids], siteIds: [UUID()]).canCreate(locations: directory.locations))
    }

    // MARK: Through the demo service

    func testLoaderAndEditorWorkAgainstTheDemoService() async throws {
        let svc = MockService()
        let church = try await svc.loadChurches()[0]
        let source = try await CalendarLoader.loadSource(service: svc, organizationId: church.id, modules: church.modules)
        XCTAssertFalse(source.directory.locations.isEmpty); XCTAssertFalse(source.moduleRules.isEmpty)
        XCTAssertNotNil(source.directory.screens.first?.screen.locationId.flatMap { id in source.directory.locations.first { $0.id == id } })
        let tz = SiteClock.timeZone(id: source.directory.sites.first?.timezone)
        let today = SiteClock.day(of: Date(), in: tz)
        let days = (0..<7).map { today.mondayOfWeek.adding(days: $0) }
        let range = CalendarLoader.paddedRange(days: days, in: tz)!
        let loaded = await CalendarLoader.loadRange(service: svc, organizationId: church.id, modules: church.modules, from: range.from, to: range.to)
        XCTAssertTrue(loaded.warnings.isEmpty, "\(loaded.warnings)")
        let data = CalendarData(snapshots: loaded.snapshots, moduleRules: source.moduleRules, names: source.names)
        let lane = source.directory.resolve(.all)
        let events = CalendarEventBuilder.events(data: data, directory: source.directory, permissions: CalendarPermissions(church), lane: lane, days: days)
        XCTAssertTrue(events.contains { $0.style == .slidesOneTime && $0.title == "Christmas Eve" })
        let kidsOnce = try XCTUnwrap(events.first { $0.style == .kidsOneTime })
        // Move it by an hour through the planner and the services, then read it back.
        let s = WallTime(kidsOnce.start, in: tz), e = WallTime(kidsOnce.end, in: tz)
        guard case .apply(let change) = CalendarEditPlanner.plan(event: kidsOnce, newStart: s.adding(minutes: 60), newEnd: e.adding(minutes: 60), in: tz, organizationId: church.id) else { return XCTFail() }
        try await CalendarEditor.apply(change, service: svc, organizationId: church.id)
        let again = await CalendarLoader.loadRange(service: svc, organizationId: church.id, modules: church.modules, from: range.from, to: range.to)
        let moved = CalendarEventBuilder.events(data: CalendarData(snapshots: again.snapshots, moduleRules: source.moduleRules, names: source.names), directory: source.directory,
                                                permissions: CalendarPermissions(church), lane: lane, days: days).first { $0.id == kidsOnce.id }
        XCTAssertEqual(moved?.start, kidsOnce.start.addingTimeInterval(3600))

        // "This date only" on the Sunday series: the date is skipped and a one-off appears at the new time.
        let series = try XCTUnwrap(events.first { $0.style == .kidsRepeating })
        let ss = WallTime(series.start, in: tz), se = WallTime(series.end, in: tz)
        guard case .choose(_, _, let choices) = CalendarEditPlanner.plan(event: series, newStart: ss.adding(minutes: 30), newEnd: se.adding(minutes: 30), in: tz, organizationId: church.id) else { return XCTFail() }
        try await CalendarEditor.apply(choices[0].change, service: svc, organizationId: church.id)
        let after = await CalendarLoader.loadRange(service: svc, organizationId: church.id, modules: church.modules, from: range.from, to: range.to)
        let ev2 = CalendarEventBuilder.events(data: CalendarData(snapshots: after.snapshots, moduleRules: source.moduleRules, names: source.names), directory: source.directory,
                                              permissions: CalendarPermissions(church), lane: lane, days: days)
        XCTAssertFalse(ev2.contains { $0.id == series.id })
        XCTAssertTrue(ev2.contains { $0.style == .kidsOneTime && $0.start == series.start.addingTimeInterval(1800) && $0.title == series.title.components(separatedBy: ": ").last })
    }
}
