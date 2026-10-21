import Foundation
import Supabase

// Scheduling against the real tables: deck_schedules / deck_series / deck_series_exceptions, schedules / kids_series / kids_series_exceptions,
// signage_slots, screen_groups and the *_series_occurrences functions. Row-level security decides who may write.

extension SupabaseService: ScheduleService {
    private func scheduled<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await guarded(work) }
        catch let e as ChurchError { throw ChurchError(ScheduleErrors.friendly(e.message)) }
    }

    private struct GroupRow: Decodable { let id: UUID; let name: String }
    private struct DatedRow: Decodable { let id: UUID; let locationId: UUID; let startsAt: Date; let endsAt: Date?; let deckId: UUID?; let playlistId: UUID? }
    private struct SeriesRow: Decodable {
        let id: UUID; let locationId: UUID; let name: String?; let days: [Int]; let startTime: String; let endTime: String
        let startDate: String; let endDate: String?; let deckIds: [UUID]?; let playlistIds: [UUID]?; let onEnd: String
    }
    private struct OccRow: Decodable {
        let seriesId: UUID; let locationId: UUID; let onDate: String; let startsAt: Date; let endsAt: Date
        let deckId: UUID?; let playlistId: UUID?; let occurrenceNo: Int?; let isOverride: Bool?
    }
    private struct SlotRow: Decodable {
        let id: UUID; let screenId: UUID?; let groupId: UUID?; let playlistId: UUID; let days: [Int]
        let startTime: String; let endTime: String; let priority: Int
    }
    private struct IdOnly: Decodable { let id: UUID }
    private struct RangeParams: Encodable {
        let pOrg: String, pFrom: String, pTo: String
        enum CodingKeys: String, CodingKey { case pOrg = "p_org", pFrom = "p_from", pTo = "p_to" }
    }
    private struct SkipRow: Encodable {
        let seriesId: String, onDate: String, action: String
        enum CodingKeys: String, CodingKey { case seriesId = "series_id", onDate = "on_date", action }
    }

    public func listScreenGroups(organizationId: UUID) async throws -> [ScreenGroup] {
        try await scheduled {
            let list: [GroupRow] = try await rows(client.from("screen_groups").select("id,name").eq("organization_id", value: organizationId.uuidString.lowercased()).order("name"))
            return list.map { ScreenGroup(id: $0.id, name: $0.name) }
        }
    }

    public func scheduleSnapshot(module: AppModule, organizationId: UUID, now: Date) async throws -> ScheduleSnapshot {
        try await scheduled {
            let org = organizationId.uuidString.lowercased()
            if module == .signage {
                let slots: [SlotRow] = try await rows(client.from("signage_slots").select("id,screen_id,group_id,playlist_id,days,start_time,end_time,priority").eq("organization_id", value: org))
                return ScheduleSnapshot(slots: slots.compactMap { r in
                    guard let a = ClockTime(db: r.startTime), let b = ClockTime(db: r.endTime) else { return nil }
                    return SignageSlot(id: r.id, screenId: r.screenId, groupId: r.groupId, playlistId: r.playlistId, days: r.days, startTime: a, endTime: b,
                                       endIsEndOfDay: r.endTime.hasPrefix("23:59:59"), priority: r.priority)
                })
            }
            guard let dated = ScheduleTable.dated(module), let seriesTable = ScheduleTable.series(module) else { return .empty }
            let nowS = ChurchJSON.formatTimestamp(now)
            let datedRows: [DatedRow] = try await rows(
                client.from(dated.rawValue).select("id,location_id,\(dated.itemColumn),starts_at,ends_at").eq("organization_id", value: org)
                    .or("ends_at.is.null,ends_at.gt.\(nowS)").order("starts_at").limit(500))
            let seriesRows: [SeriesRow] = try await rows(
                client.from(seriesTable.rawValue).select("id,location_id,name,days,start_time,end_time,start_date,end_date,\(seriesTable.rotationColumn),on_end")
                    .eq("organization_id", value: org).order("start_date"))
            // Upcoming dates are a nicety: when the function fails the list still works.
            let fn = module == .slides ? "deck_series_occurrences" : "kids_series_occurrences"
            let params = RangeParams(pOrg: org, pFrom: nowS, pTo: ChurchJSON.formatTimestamp(now.addingTimeInterval(14 * 86_400)))
            let occRows: [OccRow] = (try? await rows(try client.rpc(fn, params: params))) ?? []
            return ScheduleSnapshot(
                dated: datedRows.compactMap { r in (r.deckId ?? r.playlistId).map { DatedSchedule(id: r.id, locationId: r.locationId, itemId: $0, startsAt: r.startsAt, endsAt: r.endsAt) } },
                series: seriesRows.compactMap { r in
                    guard let a = ClockTime(db: r.startTime), let b = ClockTime(db: r.endTime), let sd = CalendarDay(string: r.startDate) else { return nil }
                    return RepeatingSeries(id: r.id, locationId: r.locationId, name: r.name, days: r.days, startTime: a, endTime: b, startDate: sd,
                                           endDate: r.endDate.flatMap { CalendarDay(string: $0) }, itemIds: r.deckIds ?? r.playlistIds ?? [], onEnd: OnEnd(rawValue: r.onEnd) ?? .loop)
                },
                occurrences: occRows.compactMap { r in
                    CalendarDay(string: r.onDate).map { SeriesOccurrence(seriesId: r.seriesId, locationId: r.locationId, onDate: $0, startsAt: r.startsAt, endsAt: r.endsAt, itemId: r.deckId ?? r.playlistId, occurrenceNo: r.occurrenceNo, isOverride: r.isOverride ?? false) }
                })
        }
    }

    public func createSchedules(_ newRows: [NewScheduleRow], organizationId: UUID) async throws {
        try await scheduled {
            for table in ScheduleTable.allCases {
                let batch = newRows.filter { $0.table == table }.map(\.values)
                if batch.isEmpty { continue }
                let created: [IdOnly] = try await rows(client.from(table.rawValue).insert(batch).select("id"))
                if created.count != batch.count { throw ChurchError("The schedule was not saved. You may not have permission.") }
            }
        }
    }

    public func deleteSchedule(table: ScheduleTable, id: UUID, organizationId: UUID) async throws {
        try await scheduled {
            let gone: [IdOnly] = try await rows(client.from(table.rawValue).delete().eq("id", value: id.uuidString.lowercased()).eq("organization_id", value: organizationId.uuidString.lowercased()).select("id"))
            if gone.isEmpty { throw ChurchError("Couldn't remove it. It may already be gone, or you may not have permission.") }
        }
    }

    public func skipSeriesDate(table: ScheduleTable, seriesId: UUID, on day: CalendarDay) async throws {
        guard let exceptions = table.exceptionsTable else { throw ChurchError("Only repeating schedules can skip a date.") }
        try await scheduled {
            let row = SkipRow(seriesId: seriesId.uuidString.lowercased(), onDate: day.string, action: "skip")
            let saved: [SeriesIdOnly] = try await rows(client.from(exceptions).upsert(row, onConflict: "series_id,on_date").select("series_id"))
            if saved.isEmpty { throw ChurchError("Couldn't skip that date. You may not have permission.") }
        }
    }
    private struct SeriesIdOnly: Decodable { let seriesId: UUID }
}

// MARK: - Calendar (range reads and row updates)

extension SupabaseService: CalendarService {
    private struct RuleRow: Decodable {
        let id: UUID; let screenId: UUID?; let groupId: UUID?; let module: String; let days: [Int]
        let startTime: String; let endTime: String; let priority: Int; let createdAt: Date?
    }

    public func scheduleRange(module: AppModule, organizationId: UUID, from: Date, to: Date) async throws -> ScheduleSnapshot {
        if module == .signage { return try await scheduleSnapshot(module: .signage, organizationId: organizationId, now: from) }
        guard let dated = ScheduleTable.dated(module), let seriesTable = ScheduleTable.series(module) else { return .empty }
        return try await scheduled {
            let org = organizationId.uuidString.lowercased()
            let fromS = ChurchJSON.formatTimestamp(from), toS = ChurchJSON.formatTimestamp(to)
            let cutoff = ChurchJSON.formatTimestamp(from.addingTimeInterval(-14 * 86_400))
            // Same filter as the website: starts before the end, and ends after the start (or is open-ended and recent).
            let datedRows: [DatedRow] = try await rows(
                client.from(dated.rawValue).select("id,location_id,\(dated.itemColumn),starts_at,ends_at").eq("organization_id", value: org)
                    .lt("starts_at", value: toS).or("ends_at.gt.\(fromS),and(ends_at.is.null,starts_at.gt.\(cutoff))").order("starts_at").limit(1000))
            let seriesRows: [SeriesRow] = try await rows(
                client.from(seriesTable.rawValue).select("id,location_id,name,days,start_time,end_time,start_date,end_date,\(seriesTable.rotationColumn),on_end")
                    .eq("organization_id", value: org).order("start_date"))
            let fn = module == .slides ? "deck_series_occurrences" : "kids_series_occurrences"
            let occRows: [OccRow] = try await rows(try client.rpc(fn, params: RangeParams(pOrg: org, pFrom: fromS, pTo: toS)))
            return ScheduleSnapshot(
                dated: datedRows.compactMap { r in (r.deckId ?? r.playlistId).map { DatedSchedule(id: r.id, locationId: r.locationId, itemId: $0, startsAt: r.startsAt, endsAt: r.endsAt) } },
                series: seriesRows.compactMap { r in
                    guard let a = ClockTime(db: r.startTime), let b = ClockTime(db: r.endTime), let sd = CalendarDay(string: r.startDate) else { return nil }
                    return RepeatingSeries(id: r.id, locationId: r.locationId, name: r.name, days: r.days, startTime: a, endTime: b, startDate: sd,
                                           endDate: r.endDate.flatMap { CalendarDay(string: $0) }, itemIds: r.deckIds ?? r.playlistIds ?? [], onEnd: OnEnd(rawValue: r.onEnd) ?? .loop)
                },
                occurrences: occRows.compactMap { r in
                    CalendarDay(string: r.onDate).map { SeriesOccurrence(seriesId: r.seriesId, locationId: r.locationId, onDate: $0, startsAt: r.startsAt, endsAt: r.endsAt, itemId: r.deckId ?? r.playlistId, occurrenceNo: r.occurrenceNo, isOverride: r.isOverride ?? false) }
                })
        }
    }

    public func listModuleRules(organizationId: UUID) async throws -> [ModuleRule] {
        try await scheduled {
            let list: [RuleRow] = try await rows(client.from("screen_schedules").select("id,screen_id,group_id,module,days,start_time,end_time,priority,created_at").eq("organization_id", value: organizationId.uuidString.lowercased()))
            return list.compactMap { r in
                guard let a = ClockTime(db: r.startTime), let b = ClockTime(db: r.endTime) else { return nil }
                return ModuleRule(id: r.id, screenId: r.screenId, groupId: r.groupId, module: r.module, days: r.days, startTime: a, endTime: b, endIsEndOfDay: r.endTime.hasPrefix("23:59:59"), priority: r.priority, createdAt: r.createdAt ?? .distantPast)
            }
        }
    }

    public func updateScheduleRow(_ table: CalendarTable, id: UUID, values: [String: RawJSON]) async throws {
        try await scheduled {
            let saved: [IdOnly] = try await rows(client.from(table.rawValue).update(values).eq("id", value: id.uuidString.lowercased()).select("id"))
            if saved.isEmpty { throw ChurchError("Couldn't change it. It may be gone, or you may not have permission.") }
        }
    }

    public func insertScheduleRow(_ table: CalendarTable, values: [String: RawJSON]) async throws {
        try await scheduled {
            let saved: [IdOnly] = try await rows(client.from(table.rawValue).insert(values).select("id"))
            if saved.isEmpty { throw ChurchError("The schedule was not saved. You may not have permission.") }
        }
    }
}
