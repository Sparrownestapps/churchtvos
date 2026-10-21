import Foundation
import Observation
import ChurchTVCore

/// One line of "Upcoming for this item".
struct UpcomingRow: Identifiable {
    enum Kind { case once, series, slot }
    let id: UUID
    let kind: Kind
    let title: String
    let detail: String
    var next: String?
    var table: ScheduleTable
    var series: RepeatingSeries?
    /// The date "Skip next date" would skip.
    var skipDate: CalendarDay?
    var skipLabel: String?
}

struct LocationGroup: Identifiable {
    let id: String
    let site: Site?
    let locations: [Location]
}

/// State and actions of the Schedule sheet (one per presentation).
@MainActor
@Observable
final class ScheduleSheetModel {
    let target: ScheduleTarget
    @ObservationIgnored unowned let app: AppModel

    var form: ScheduleForm
    var signage = SignageForm()
    private(set) var snapshot: ScheduleSnapshot = .empty
    private(set) var groups: [ScreenGroup] = []
    private(set) var isLoading = true
    private(set) var isSaving = false
    var errorText: String?
    var successText: String?
    /// Error of a delete / skip (shown at the top of the Upcoming section).
    var upcomingError: String?
    var seriesToDelete: RepeatingSeries?

    init(target: ScheduleTarget, app: AppModel) {
        self.target = target
        self.app = app
        form = ScheduleForm.initial(for: target, in: .current)
        #if DEBUG
        // Test launch arguments: `-schedmode repeat` opens the weekly form, `-schedpick` ticks the first location / screen.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-schedmode") { form.mode = .repeating }
        debugPick = args.contains("-schedpick")
        #endif
    }
    private var debugPick = false

    var module: AppModule { target.module }
    var isSignage: Bool { module == .signage }
    private var content: ContentModel { app.content }
    private var service: any ChurchService { app.service }

    // MARK: Loading

    func load() async {
        isLoading = true
        await content.loadSupport()
        switch module {
        case .kids: await content.load(.kids)
        case .slides: await content.load(.slides)
        case .signage: await content.load(.signage)
        }
        if let org = app.church?.id {
            if isSignage { groups = (try? await service.listScreenGroups(organizationId: org)) ?? [] }
            await reloadSnapshot()
        }
        if !isSignage, form.locationIds.isEmpty, candidateLocations.count == 1 { form.locationIds = [candidateLocations[0].id] }
        #if DEBUG
        if debugPick {
            if isSignage { if let s = app.screens.first(where: { $0.id == UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000103") }) { signage.targets = [.screen(s.id)]; signage.higherPriority = true } }
            else if let l = orderedLocationIds.first { form.locationIds = [l] }
        }
        #endif
        isLoading = false
    }

    func reloadSnapshot() async {
        guard let org = app.church?.id else { return }
        do {
            snapshot = try await service.scheduleSnapshot(module: module, organizationId: org, now: Date())
            upcomingError = nil
        } catch {
            upcomingError = Formatting.message(for: error)
        }
    }

    // MARK: Locations and time zones (Kids, Slides)

    /// Kids: locations tagged Kids. Slides: tagged Slides, and also Kids rooms (the website offers them too).
    /// Only where the member may edit (site scope).
    var candidateLocations: [Location] {
        guard let church = app.church else { return [] }
        return content.locations.filter { l in
            (module == .kids ? l.uses(.kids) : l.uses(.slides) || l.uses(.kids))
                && ContentPermissions.inSiteScope(role: church.role, siteIds: church.siteIds, siteId: l.siteId)
        }
    }

    /// Candidate locations grouped by site, in site name order.
    var locationGroups: [LocationGroup] {
        let by = Dictionary(grouping: candidateLocations, by: { $0.siteId })
        return by.keys.sorted { (siteName($0)).localizedCaseInsensitiveCompare(siteName($1)) == .orderedAscending }
            .map { key in LocationGroup(id: key?.uuidString ?? "none", site: content.sites.first { $0.id == key },
                                        locations: by[key]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
    }
    var orderedLocationIds: [UUID] { locationGroups.flatMap { $0.locations.map(\.id) } }
    private func siteName(_ id: UUID?) -> String { content.sites.first { $0.id == id }?.name ?? "" }
    /// Slides: a room that is only tagged for Kids (labelled "Kids" in the list).
    func isKidsOnlyRoom(_ l: Location) -> Bool { module == .slides && !l.uses(.slides) }
    var taggedSlidesCount: Int { content.locations.filter { $0.uses(.slides) }.count }

    func location(_ id: UUID) -> Location? { content.locations.first { $0.id == id } }
    func locationName(_ id: UUID) -> String { location(id)?.name ?? "Unknown location" }
    func timeZone(forLocation id: UUID) -> TimeZone {
        SiteClock.timeZone(id: content.sites.first { $0.id == location(id)?.siteId }?.timezone)
    }

    /// The zones the entered times are in: the chosen locations' (or screens'), or the first offered location's.
    var activeZones: [TimeZone] {
        var ids: [TimeZone] = []
        func add(_ tz: TimeZone) { if !ids.contains(where: { $0.identifier == tz.identifier }) { ids.append(tz) } }
        if isSignage {
            for t in signage.targets { if let s = t.screenId, let info = app.screens.first(where: { $0.id == s }) { add(info.timeZone) } }
            if ids.isEmpty, let any = app.screens.first { add(any.timeZone) }
        } else {
            for l in orderedLocationIds where form.locationIds.contains(l) { add(timeZone(forLocation: l)) }
            if ids.isEmpty, let first = orderedLocationIds.first { add(timeZone(forLocation: first)) }
        }
        return ids
    }

    // MARK: Rotation choices

    /// Items that can be chosen for a week of the rotation (all decks, or all Kids playlists).
    var rotationChoices: [(id: UUID, name: String)] {
        module == .slides ? content.decks.map { ($0.id, $0.name) } : content.kids.map { ($0.id, $0.name) }
    }

    func itemName(_ id: UUID) -> String {
        if id == target.id { return target.name }
        return (content.decks.map { ($0.id, $0.name) } + content.kids.map { ($0.id, $0.name) } + content.signage.map { ($0.id, $0.name) }).first { $0.0 == id }?.1 ?? "Another item"
    }

    // MARK: Signage targets

    func screenName(_ id: UUID) -> String { app.screens.first { $0.id == id }?.screen.displayName ?? "Screen" }
    func targetName(_ t: SignageTargetRef) -> String {
        if let s = t.screenId { return screenName(s) }
        if let g = t.groupId { return "Group: " + (groups.first { $0.id == g }?.name ?? "Unknown") }
        return "Screen"
    }
    func toggle(_ t: SignageTargetRef) {
        if let i = signage.targets.firstIndex(of: t) { signage.targets.remove(at: i) } else { signage.targets.append(t) }
    }
    /// Signage slots belong to the whole church; the server only lets editors with access to all sites change them.
    var signageNeedsAllSites: Bool { isSignage && !(app.church?.hasAllSites ?? true) }

    // MARK: Validation, hints

    var problem: String? { isSignage ? signage.problem : form.problem }

    var hints: [String] {
        if isSignage {
            return ScheduleOverlap.signageHints(form: signage, existing: snapshot.slots, itemName: itemName, targetName: targetName)
        }
        return ScheduleOverlap.hints(target: target, form: form, snapshot: snapshot, itemName: itemName, locationName: locationName,
                                     timeZone: timeZone(forLocation:), orderedLocations: orderedLocationIds)
    }

    // MARK: Saving

    func submit() async {
        guard let org = app.church?.id, !isSaving else { return }
        isSaving = true; errorText = nil; successText = nil
        defer { isSaving = false }
        do {
            let rows: [NewScheduleRow]
            if isSignage {
                rows = try ScheduleRowBuilder.slotRows(playlistId: target.id, form: signage, organizationId: org, existing: snapshot.slots)
            } else {
                rows = try ScheduleRowBuilder.rows(target: target, form: form, organizationId: org, orderedLocations: orderedLocationIds, timeZone: timeZone(forLocation:))
            }
            try await service.createSchedules(rows, organizationId: org)
            Haptics.success()
            let n = rows.count
            successText = isSignage ? "Added \(n) slot\(n == 1 ? "" : "s")."
                : form.mode == .once ? "Scheduled at \(n) location\(n == 1 ? "" : "s")." : "Repeating schedule added at \(n) location\(n == 1 ? "" : "s")."
            await reloadSnapshot()
            await app.loadSchedule()
        } catch {
            Haptics.failure()
            errorText = Formatting.message(for: error)
        }
    }

    func delete(_ row: UpcomingRow) async {
        guard let org = app.church?.id else { return }
        do {
            try await service.deleteSchedule(table: row.table, id: row.id, organizationId: org)
            upcomingError = nil; successText = nil
            await reloadSnapshot()
            await app.loadSchedule()
        } catch { upcomingError = Formatting.message(for: error) }
    }

    func skipNext(_ row: UpcomingRow) async {
        guard let day = row.skipDate else { return }
        do {
            try await service.skipSeriesDate(table: row.table, seriesId: row.id, on: day)
            upcomingError = nil; successText = nil
            await reloadSnapshot()
            await app.loadSchedule()
        } catch { upcomingError = Formatting.message(for: error) }
    }

    // MARK: Upcoming for this item

    var upcoming: [UpcomingRow] {
        if isSignage {
            return snapshot.slots.filter { $0.playlistId == target.id }
                .sorted { ($0.priority, $0.startTime.minutes) > ($1.priority, $1.startTime.minutes) }
                .map { s in
                    UpcomingRow(id: s.id, kind: .slot, title: "\(targetName(s.target)) · \(ScheduleDays.label(s.days))",
                                detail: ScheduleText.timeRange(s.startTime, s.endTime, endOfDay: s.endIsEndOfDay) + (s.priority != 0 ? " · priority \(s.priority)" : ""),
                                table: .signageSlots)
                }
        }
        guard let datedTable = ScheduleTable.dated(module), let seriesTable = ScheduleTable.series(module) else { return [] }
        var rows: [(Date, UpcomingRow)] = []
        for d in snapshot.dated where d.itemId == target.id {
            let tz = timeZone(forLocation: d.locationId)
            rows.append((d.startsAt, UpcomingRow(id: d.id, kind: .once, title: ScheduleText.rangeText(d.startsAt, d.endsAt, in: tz), detail: locationLine(d.locationId, tz),
                                                 table: datedTable)))
        }
        for s in snapshot.series where s.itemIds.contains(target.id) {
            let tz = timeZone(forLocation: s.locationId)
            let mine = snapshot.occurrences.filter { $0.seriesId == s.id && $0.itemId == target.id }
            var detail = [locationLine(s.locationId, tz), "from \(ScheduleText.day(s.startDate))"]
            if let e = s.endDate { detail.append("until \(ScheduleText.day(e))") }
            if s.itemIds.count > 1 { detail.append("rotation of \(s.itemIds.count), \(s.onEnd == .loop ? "starts over" : "then stops")") }
            if let n = s.name, !n.isEmpty { detail.insert(n, at: 0) }
            let nextText = mine.isEmpty ? "No dates in the next 14 days" : "Next: " + mine.prefix(3).map { ScheduleText.day($0.onDate) }.joined(separator: " · ")
            rows.append((mine.first?.startsAt ?? .distantFuture, UpcomingRow(
                id: s.id, kind: .series, title: "Every \(ScheduleDays.label(s.days)), \(ScheduleText.timeRange(s.startTime, s.endTime))",
                detail: detail.joined(separator: " · "), next: nextText, table: seriesTable, series: s,
                skipDate: mine.first?.onDate, skipLabel: mine.first.map { "Skip \(ScheduleText.day($0.onDate))" })))
        }
        return rows.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func locationLine(_ id: UUID, _ tz: TimeZone) -> String {
        SiteClock.differsFromDevice(tz) ? "\(locationName(id)) · \(tz.abbreviation(for: Date()) ?? tz.identifier)" : locationName(id)
    }
}
