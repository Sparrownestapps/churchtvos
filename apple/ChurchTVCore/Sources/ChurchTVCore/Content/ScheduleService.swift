import Foundation

/// Scheduling API: dated schedules and repeating series (Kids, Slides) and weekly Signage slots.
/// `SupabaseService` writes the real tables; `MockService` keeps them in memory (demo mode). Every method has a default that throws,
/// so other conformers (and the Mac app) keep compiling. Server refusals pass through as readable `ChurchError`s.
public protocol ScheduleService: Sendable {
    /// Screen groups (`screen_groups`).
    func listScreenGroups(organizationId: UUID) async throws -> [ScreenGroup]
    /// Existing schedules of one module: Kids/Slides = dated rows not yet over, all repeating series and their occurrences for the
    /// next 14 days (from the `*_series_occurrences` functions; empty if the function fails). Signage = the weekly slots.
    func scheduleSnapshot(module: AppModule, organizationId: UUID, now: Date) async throws -> ScheduleSnapshot
    /// Inserts the rows (one batch per table).
    func createSchedules(_ rows: [NewScheduleRow], organizationId: UUID) async throws
    /// Deletes one dated row, series (its exceptions go with it) or slot.
    func deleteSchedule(table: ScheduleTable, id: UUID, organizationId: UUID) async throws
    /// "Skip next date" for a repeating series: writes an exception with action 'skip' (the rotation waits).
    func skipSeriesDate(table: ScheduleTable, seriesId: UUID, on day: CalendarDay) async throws
}

public extension ScheduleService {
    private var unavailable: ChurchError { ChurchError("Scheduling is not available here.") }
    func listScreenGroups(organizationId: UUID) async throws -> [ScreenGroup] { throw unavailable }
    func scheduleSnapshot(module: AppModule, organizationId: UUID, now: Date) async throws -> ScheduleSnapshot { throw unavailable }
    func createSchedules(_ rows: [NewScheduleRow], organizationId: UUID) async throws { throw unavailable }
    func deleteSchedule(table: ScheduleTable, id: UUID, organizationId: UUID) async throws { throw unavailable }
    func skipSeriesDate(table: ScheduleTable, seriesId: UUID, on day: CalendarDay) async throws { throw unavailable }
}

/// Maps server messages to text for people.
public enum ScheduleErrors {
    public static func friendly(_ message: String) -> String {
        let m = message.lowercased()
        if m.contains("row-level security") || m.contains("permission denied") {
            return "You do not have permission to schedule this. Signage slots apply to the whole church, so they need an editor with access to all sites. Ask a church admin."
        }
        if m.contains("no access") { return "You do not have access to this part of the church. Ask a church admin." }
        if m.contains("check constraint") || m.contains("violates check") { return "Those times are not valid. Check the days, times and dates." }
        if m.contains("foreign key") { return "That item or location no longer exists. Close this and try again." }
        return ContentErrors.friendly(message)
    }
}
