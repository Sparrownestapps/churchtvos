import Foundation

// Back-end API for the native calendar. Reuses ScheduleService (create / delete / skip a date) and the *_series_occurrences wrappers;
// this adds range reads and the row updates that dragging needs. Defaults throw so other conformers keep compiling.

/// A "which module does this screen run" rule (`screen_schedules`). Weekly, like a signage slot; `module` is kids, signage, slides or off.
public struct ModuleRule: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var screenId: UUID?
    public var groupId: UUID?
    public var module: String
    public var days: [Int]
    public var startTime: ClockTime
    public var endTime: ClockTime
    public var endIsEndOfDay: Bool
    public var priority: Int
    public var createdAt: Date
    public init(id: UUID, screenId: UUID? = nil, groupId: UUID? = nil, module: String, days: [Int], startTime: ClockTime, endTime: ClockTime,
                endIsEndOfDay: Bool = false, priority: Int = 0, createdAt: Date = .distantPast) {
        self.id = id; self.screenId = screenId; self.groupId = groupId; self.module = module; self.days = days
        self.startTime = startTime; self.endTime = endTime; self.endIsEndOfDay = endIsEndOfDay; self.priority = priority; self.createdAt = createdAt
    }
}

/// Tables the calendar may update (the dated and series tables, signage slots and module rules).
public enum CalendarTable: String, Sendable, CaseIterable {
    case deckSchedules = "deck_schedules", deckSeries = "deck_series"
    case kidsSchedules = "schedules", kidsSeries = "kids_series"
    case signageSlots = "signage_slots", screenSchedules = "screen_schedules"

    public init(_ t: ScheduleTable) {
        switch t {
        case .deckSchedules: self = .deckSchedules
        case .deckSeries: self = .deckSeries
        case .kidsSchedules: self = .kidsSchedules
        case .kidsSeries: self = .kidsSeries
        case .signageSlots: self = .signageSlots
        }
    }
}

public protocol CalendarService: Sendable {
    /// Existing schedules of one module that touch [from, to): Kids/Slides = dated rows overlapping the range (an open-ended one that
    /// started up to 14 days before counts), every repeating series, and the series occurrences inside the range from the
    /// `kids_series_occurrences` / `deck_series_occurrences` functions. Signage = the weekly slots (the range does not matter).
    func scheduleRange(module: AppModule, organizationId: UUID, from: Date, to: Date) async throws -> ScheduleSnapshot
    /// Module switching rules (`screen_schedules`) of the whole church.
    func listModuleRules(organizationId: UUID) async throws -> [ModuleRule]
    /// Updates columns of one row. Throws a readable error when nothing changed (no permission, or the row is gone).
    func updateScheduleRow(_ table: CalendarTable, id: UUID, values: [String: RawJSON]) async throws
    /// Inserts one row (copy of a weekly rule for "only this day").
    func insertScheduleRow(_ table: CalendarTable, values: [String: RawJSON]) async throws
}

public extension CalendarService {
    private var unavailable: ChurchError { ChurchError("The calendar is not available here.") }
    func scheduleRange(module: AppModule, organizationId: UUID, from: Date, to: Date) async throws -> ScheduleSnapshot { throw unavailable }
    func listModuleRules(organizationId: UUID) async throws -> [ModuleRule] { throw unavailable }
    func updateScheduleRow(_ table: CalendarTable, id: UUID, values: [String: RawJSON]) async throws { throw unavailable }
    func insertScheduleRow(_ table: CalendarTable, values: [String: RawJSON]) async throws { throw unavailable }
}
