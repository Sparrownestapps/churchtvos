import Foundation

// Turning a drag (move / resize) into the database changes, and running them. Mirrors `onChange` in dashboard/src/calendar/CalendarPage.tsx:
//  - one-off Kids / Slides: starts_at / ends_at are updated directly (open-ended ones keep ends_at null);
//  - repeating occurrence: the website only offers "change the whole series"; the phone adds "This date only", which uses the existing
//    exception mechanism (skip that date) plus a one-off at the new time;
//  - signage slot / module switch: weekly rows. One day: updated. Several days: change every day (shifted), or only this day (a copy
//    for the new day, the old day leaves the rule).

public enum CalendarChange: Equatable, Sendable {
    case dated(table: ScheduleTable, id: UUID, startsAt: Date, endsAt: Date?)
    case update(table: CalendarTable, id: UUID, values: [String: RawJSON])
    /// Skip `day` of the series and create `oneOff` (its `id` is in the row values, so a failed skip can undo the insert).
    case thisDateOnly(seriesTable: ScheduleTable, seriesId: UUID, day: CalendarDay, oneOffId: UUID, oneOff: NewScheduleRow)
    case splitRule(table: CalendarTable, id: UUID, remainingDays: [Int], copy: [String: RawJSON])
}

public struct CalendarChoice: Equatable, Sendable, Identifiable {
    public var label: String
    public var hint: String?
    public var change: CalendarChange
    public var id: String { label }
}

public enum CalendarEditPlan: Equatable, Sendable {
    case unchanged
    case rejected(String)
    case apply(CalendarChange)
    case choose(title: String, message: String, choices: [CalendarChoice])
}

public enum CalendarEditPlanner {
    /// `newStart` / `newEnd` are wall times in `tz` (the grid snaps them to 15 minutes before calling).
    public static func plan(event: CalendarEvent, newStart: WallTime, newEnd: WallTime, in tz: TimeZone, organizationId: UUID, newId: () -> UUID = UUID.init) -> CalendarEditPlan {
        guard event.editable else { return .rejected(event.lockReason ?? "You can only view this.") }
        let newStart = newStart.normalized, newEnd = newEnd.normalized
        let oldStart = WallTime(event.start, in: tz)
        let oldEnd = WallTime(event.end, in: tz)
        if newStart == oldStart && newEnd == oldEnd { return .unchanged }
        guard newEnd > newStart else { return .rejected("The end time must be after the start time.") }

        switch event.source {
        case .oneOff(_, let table, let schedule, let open):
            return .apply(.dated(table: table, id: schedule.id, startsAt: newStart.instant(in: tz), endsAt: open ? nil : newEnd.instant(in: tz)))

        case .occurrence(let module, let seriesTable, let series, let occ):
            guard let times = ruleTimes(newStart, newEnd) else { return .rejected(pastMidnight) }
            let diff = newStart.day.days(since: oldStart.day)
            func shift(_ d: CalendarDay) -> CalendarDay { d.adding(days: diff) }
            var whole: [String: RawJSON] = [
                "days": .array(Array(Set(series.days.map { (($0 + diff) % 7 + 7) % 7 })).sorted().map { .number(Double($0)) }),
                "start_time": .string(times.start), "end_time": .string(times.end),
                "start_date": .string(shift(series.startDate).string),
            ]
            whole["end_date"] = series.endDate.map { .string(shift($0).string) } ?? .null
            var choices: [CalendarChoice] = []
            if let item = occ.itemId, let datedTable = ScheduleTable.dated(module) {
                let id = newId()
                let v: [String: RawJSON] = [
                    "id": .string(id.uuidString.lowercased()),
                    "organization_id": .string(organizationId.uuidString.lowercased()), "location_id": .string(occ.locationId.uuidString.lowercased()),
                    datedTable.itemColumn: .string(item.uuidString.lowercased()),
                    "starts_at": .string(ChurchJSON.formatTimestamp(newStart.instant(in: tz))), "ends_at": .string(ChurchJSON.formatTimestamp(newEnd.instant(in: tz))),
                ]
                let rotation = series.itemIds.count > 1 ? " The rotation waits for a skipped date, so the next date plays the same week again." : ""
                choices.append(CalendarChoice(label: "This date only", hint: "Skips \(ScheduleText.day(occ.onDate)) and adds a one-time schedule at the new time.\(rotation)",
                                              change: .thisDateOnly(seriesTable: seriesTable, seriesId: series.id, day: occ.onDate, oneOffId: id, oneOff: NewScheduleRow(table: datedTable, values: v))))
            }
            let shiftText = diff == 0 ? "" : "It will run \(diff > 0 ? "+" : "")\(diff) day\(abs(diff) == 1 ? "" : "s") from now on, "
            choices.append(CalendarChoice(label: "Whole series", hint: "\(shiftText.isEmpty ? "Every date, at" : shiftText + "at") \(clock(newStart))-\(clock(newEnd)). Skipped or changed dates keep their original dates.",
                                          change: .update(table: CalendarTable(seriesTable), id: series.id, values: whole)))
            return .choose(title: "Change just this date, or the whole repeating schedule?",
                           message: "“\(event.title)” repeats. Moving it changes the times for the dates you choose.", choices: choices)

        case .slot(let slot):
            return weekly(table: .signageSlots, id: slot.id, days: slot.days, event: event, oldStart: oldStart, newStart: newStart, newEnd: newEnd, label: event.title,
                          copyBase: slotBase(slot, organizationId), organizationId: organizationId)
        case .moduleRule(let rule):
            return weekly(table: .screenSchedules, id: rule.id, days: rule.days, event: event, oldStart: oldStart, newStart: newStart, newEnd: newEnd, label: event.title,
                          copyBase: ruleBase(rule, organizationId), organizationId: organizationId)
        }
    }

    static let pastMidnight = "A block can't run past midnight. Make it end by midnight, or add a second block for the next day."

    static func clock(_ w: WallTime) -> String { ScheduleText.time(ClockTime(w.minutes / 60 % 24, w.minutes % 60)) }

    /// "HH:MM" start and "HH:MM" / "23:59:59" end for a weekly row, or nil when it runs past midnight.
    static func ruleTimes(_ start: WallTime, _ end: WallTime) -> (start: String, end: String)? {
        let endMinutes: Int
        if end.day == start.day { endMinutes = end.minutes }
        else if end.day == start.day.adding(days: 1), end.minutes == 0 { endMinutes = 1440 }
        else { return nil }
        guard endMinutes > start.minutes else { return nil }
        let s = ClockTime(start.minutes / 60, start.minutes % 60)
        let e = endMinutes >= 1440 ? "23:59:59" : ClockTime(endMinutes / 60, endMinutes % 60).dbString
        return (s.dbString, e)
    }

    private static func slotBase(_ s: SignageSlot, _ org: UUID) -> [String: RawJSON] {
        var v: [String: RawJSON] = ["organization_id": .string(org.uuidString.lowercased()), "playlist_id": .string(s.playlistId.uuidString.lowercased()), "priority": .number(Double(s.priority))]
        if let id = s.screenId { v["screen_id"] = .string(id.uuidString.lowercased()) }
        if let id = s.groupId { v["group_id"] = .string(id.uuidString.lowercased()) }
        return v
    }
    private static func ruleBase(_ r: ModuleRule, _ org: UUID) -> [String: RawJSON] {
        var v: [String: RawJSON] = ["organization_id": .string(org.uuidString.lowercased()), "module": .string(r.module), "priority": .number(Double(r.priority))]
        if let id = r.screenId { v["screen_id"] = .string(id.uuidString.lowercased()) }
        if let id = r.groupId { v["group_id"] = .string(id.uuidString.lowercased()) }
        return v
    }

    private static func weekly(table: CalendarTable, id: UUID, days: [Int], event: CalendarEvent, oldStart: WallTime, newStart: WallTime, newEnd: WallTime, label: String,
                               copyBase: [String: RawJSON], organizationId: UUID) -> CalendarEditPlan {
        guard let times = ruleTimes(newStart, newEnd) else { return .rejected(pastMidnight) }
        let newDow = newStart.day.weekday, oldDow = oldStart.day.weekday
        let timeValues: [String: RawJSON] = ["start_time": .string(times.start), "end_time": .string(times.end)]
        func num(_ d: [Int]) -> RawJSON { .array(d.sorted().map { .number(Double($0)) }) }
        if days.count <= 1 {
            return .apply(.update(table: table, id: id, values: timeValues.merging(["days": num([newDow])]) { a, _ in a }))
        }
        let delta = (newDow - oldDow + 7) % 7
        let all = Array(Set(days.map { ($0 + delta) % 7 }))
        var copy = copyBase.merging(timeValues) { a, _ in a }
        copy["days"] = num([newDow])
        return .choose(
            title: "This rule repeats on several days",
            message: "“\(label)” runs \(days.count) days a week, and rules repeat every week (there is no one-time version).",
            choices: [
                CalendarChoice(label: "Change every day of the rule", hint: delta == 0 ? "same days, new times" : "all days move \(delta) day\(delta == 1 ? "" : "s") later",
                               change: .update(table: table, id: id, values: timeValues.merging(["days": num(all)]) { a, _ in a })),
                CalendarChoice(label: "Only \(ScheduleDays.fullNames[oldDow])s", hint: "\(ScheduleDays.fullNames[oldDow]) leaves the rule and gets its own rule on \(ScheduleDays.fullNames[newDow])s",
                               change: .splitRule(table: table, id: id, remainingDays: days.filter { $0 != oldDow }, copy: copy)),
            ])
    }
}

public enum CalendarEditor {
    /// Runs one change through the services. Errors are readable `ChurchError`s.
    public static func apply(_ change: CalendarChange, service: any ChurchService, organizationId: UUID) async throws {
        switch change {
        case .dated(let table, let id, let startsAt, let endsAt):
            try await service.updateScheduleRow(CalendarTable(table), id: id, values: [
                "starts_at": .string(ChurchJSON.formatTimestamp(startsAt)),
                "ends_at": endsAt.map { .string(ChurchJSON.formatTimestamp($0)) } ?? .null,
            ])
        case .update(let table, let id, let values):
            try await service.updateScheduleRow(table, id: id, values: values)
        case .thisDateOnly(let seriesTable, let seriesId, let day, let oneOffId, let oneOff):
            // One-off first (a one-off overlapping the repeat replaces it on the TV anyway), then skip the date. If the skip fails the
            // new one-off is removed again so nothing is left half done.
            try await service.createSchedules([oneOff], organizationId: organizationId)
            do { try await service.skipSeriesDate(table: seriesTable, seriesId: seriesId, on: day) }
            catch {
                if let t = ScheduleTable.dated(seriesTable == .deckSeries ? .slides : .kids) { try? await service.deleteSchedule(table: t, id: oneOffId, organizationId: organizationId) }
                throw error
            }
        case .splitRule(let table, let id, let remaining, let copy):
            try await service.insertScheduleRow(table, values: copy)
            try await service.updateScheduleRow(table, id: id, values: ["days": .array(remaining.sorted().map { .number(Double($0)) })])
        }
    }
}
