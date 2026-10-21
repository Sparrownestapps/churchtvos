import Foundation

/// Loads what the calendar shows: the church's rooms and screens (static) and the schedules of a date range.
/// Everything goes through the service protocols, so demo mode (`MockService`) works unchanged.
public struct CalendarSource: Sendable {
    public var directory: CalendarDirectory
    public var names: [UUID: String]
    public var moduleRules: [ModuleRule]
    /// Modules that failed to load (shown as a note, the rest of the calendar still works).
    public var warnings: [String]
}

public enum CalendarLoader {
    /// Screens, groups, sites, locations, item names and module rules. `modules` = what the member has (and the church has live).
    public static func loadSource(service: any ChurchService, organizationId: UUID, modules: [AppModule]) async throws -> CalendarSource {
        async let screensQ = service.listScreens(organizationId: organizationId)
        async let groupsQ = try? service.listScreenGroups(organizationId: organizationId)
        async let sitesQ = try? service.listSites(organizationId: organizationId)
        async let locationsQ = try? service.listLocations(organizationId: organizationId)
        async let kidsQ: [Playlist]? = modules.contains(.kids) ? try? service.listPlaylists(kind: .kids, organizationId: organizationId) : nil
        async let signageQ: [Playlist]? = modules.contains(.signage) ? try? service.listPlaylists(kind: .signage, organizationId: organizationId) : nil
        async let decksQ: [SlideDeck]? = modules.contains(.slides) ? try? service.listDecks(organizationId: organizationId) : nil
        async let rulesQ: [ModuleRule]? = try? service.listModuleRules(organizationId: organizationId)
        let screens = try await screensQ
        let (groups, sites, locations, kids, signage, decks, rules) = await (groupsQ, sitesQ, locationsQ, kidsQ, signageQ, decksQ, rulesQ)
        var names: [UUID: String] = [:]
        for p in (kids ?? []) + (signage ?? []) { names[p.id] = p.name }
        for d in decks ?? [] { names[d.id] = d.name }
        var warnings: [String] = []
        if locations == nil { warnings.append("Locations did not load.") }
        return CalendarSource(directory: CalendarDirectory(screens: screens, groups: groups ?? [], locations: locations ?? [], sites: sites ?? []),
                              names: names, moduleRules: rules ?? [], warnings: warnings)
    }

    /// The schedules touching [from, to) for each module. A module that fails is left out and reported in `warnings`.
    public static func loadRange(service: any ChurchService, organizationId: UUID, modules: [AppModule], from: Date, to: Date) async -> (snapshots: [AppModule: ScheduleSnapshot], warnings: [String]) {
        var out: [AppModule: ScheduleSnapshot] = [:]
        var warnings: [String] = []
        await withTaskGroup(of: (AppModule, Result<ScheduleSnapshot, Error>).self) { group in
            for m in modules {
                group.addTask {
                    do { return (m, .success(try await service.scheduleRange(module: m, organizationId: organizationId, from: from, to: to))) }
                    catch { return (m, .failure(error)) }
                }
            }
            for await (m, r) in group {
                switch r {
                case .success(let s): out[m] = s
                case .failure(let e): warnings.append("\(m.displayName) schedules did not load: \(Formatting.message(for: e))")
                }
            }
        }
        return (out, warnings.sorted())
    }

    /// The visible days padded by a day each side (an event may cross midnight), as instants in `tz`.
    public static func paddedRange(days: [CalendarDay], in tz: TimeZone) -> (from: Date, to: Date)? {
        guard let a = days.first, let b = days.last else { return nil }
        return (SiteClock.instant(day: a.adding(days: -1), time: ClockTime(0), in: tz), SiteClock.instant(day: b.adding(days: 2), time: ClockTime(0), in: tz))
    }
}
