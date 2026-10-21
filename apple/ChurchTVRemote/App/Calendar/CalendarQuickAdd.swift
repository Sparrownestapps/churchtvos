import SwiftUI
import ChurchTVCore
import ChurchTVCalendar

/// "Add" sheet for a time range dragged out on the calendar. Writes through Core's `ScheduleRowBuilder` (the same rows as the ScheduleSheet):
/// a one-time Kids playlist or Slides deck in the chosen rooms, or a weekly Signage slot on the chosen screens. "More options" opens the
/// full ScheduleSheet for the chosen item (repeating schedules, rotations, overlap hints).
struct CalendarQuickAdd: View {
    let request: CalendarCreateRequest
    let model: CalendarModel
    let onOpenFull: (ScheduleTarget) -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable, Hashable { let id: UUID; let name: String }
    @State private var kind: AppModule?
    @State private var items: [AppModule: [Item]] = [:]
    @State private var itemId: UUID?
    @State private var rooms: Set<UUID> = []
    @State private var screens: Set<UUID> = []
    @State private var start: Date
    @State private var end: Date
    @State private var saving = false
    @State private var loading = true
    @State private var errorText: String?

    init(request: CalendarCreateRequest, model: CalendarModel, onOpenFull: @escaping (ScheduleTarget) -> Void) {
        self.request = request; self.model = model; self.onOpenFull = onOpenFull
        let (s, e) = Self.pickerTimes(request)
        _start = State(initialValue: s); _end = State(initialValue: e)
    }

    private static func pickerTimes(_ r: CalendarCreateRequest) -> (Date, Date) {
        func t(_ m: Int) -> ClockTime { m >= 1440 ? ClockTime(23, 59) : ClockTime(m / 60, m % 60) }
        return (SiteClock.wallDate(day: r.day, time: t(r.startMinute)), SiteClock.wallDate(day: r.day, time: t(r.endMinute)))
    }

    private var directory: CalendarDirectory { model.directory }
    private var perms: CalendarPermissions { model.permissions }

    /// Rooms of the lane that can run `module` and that the member may edit.
    private func roomsFor(_ module: AppModule) -> [Location] {
        directory.locations.filter { request.locationIds.contains($0.id) && CalendarLocations.runs(module, $0) && perms.canEdit(module, siteId: $0.siteId) }
    }
    private var laneScreens: [ScreenInfo] { directory.screens.filter { request.lane.screenIds.contains($0.id) } }
    private var kinds: [AppModule] {
        [AppModule.kids, .slides, .signage].filter { m in
            guard model.church.modules.contains(m) else { return false }
            return m == .signage ? (perms.canEditSignage && (!laneScreens.isEmpty || !request.lane.groupIds.isEmpty)) : !roomsFor(m).isEmpty
        }
    }
    private var day: CalendarDay { request.day }
    private var startTime: ClockTime { SiteClock.wallParts(start).time }
    private var endTime: ClockTime { SiteClock.wallParts(end).time }

    var body: some View {
        NavigationStack {
            Form {
                if kinds.isEmpty {
                    Section { Text("There is nothing you can schedule here. Pick a room your church uses for Kids or Slides, or a screen for Signage.").foregroundStyle(.secondary) }
                } else {
                    Section("What") {
                        if kinds.count > 1 {
                            Picker("Type", selection: Binding(get: { kind ?? kinds[0] }, set: { kind = $0; itemId = nil; pickDefaults() })) {
                                ForEach(kinds) { Text($0.displayName).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        let list = items[currentKind] ?? []
                        if loading { ProgressView() }
                        else if list.isEmpty { Text("Nothing to schedule yet. Create a \(currentKind == .slides ? "deck" : "playlist") first.").foregroundStyle(.secondary) }
                        else {
                            Picker(currentKind == .slides ? "Deck" : "Playlist", selection: Binding(get: { itemId ?? list[0].id }, set: { itemId = $0 })) {
                                ForEach(list) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                    Section {
                        LabeledContent("Day", value: ScheduleText.day(day))
                        DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    } header: { Text("When") } footer: {
                        Text(currentKind == .signage ? "Signage slots repeat every \(ScheduleDays.fullNames[day.weekday]). Times are in \(request.timeZone.identifier)." : "One time, in \(request.timeZone.identifier).")
                    }
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    Section("Where") {
                        if currentKind == .signage {
                            if let g = request.lane.groupIds.first, case .group = request.lane.lane {
                                Label("Group: \(directory.groups.first { $0.id == g }?.name ?? "")", systemImage: "rectangle.3.group")
                            } else {
                                ForEach(laneScreens) { s in
                                    Toggle(isOn: Binding(get: { screens.contains(s.id) }, set: { if $0 { screens.insert(s.id) } else { screens.remove(s.id) } })) {
                                        VStack(alignment: .leading) { Text(s.screen.displayName); if !s.locationLine.isEmpty { Text(s.locationLine).font(.caption).foregroundStyle(.secondary) } }
                                    }
                                }
                            }
                        } else {
                            ForEach(roomsFor(currentKind)) { l in
                                Toggle(isOn: Binding(get: { rooms.contains(l.id) }, set: { if $0 { rooms.insert(l.id) } else { rooms.remove(l.id) } })) {
                                    VStack(alignment: .leading) { Text(l.name); if let s = directory.sites.first(where: { $0.id == l.siteId }) { Text(s.name).font(.caption).foregroundStyle(.secondary) } }
                                }
                            }
                        }
                    }
                    if let e = errorText { Section { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
                    Section {
                        Button { Task { await save() } } label: { HStack { Spacer(); if saving { ProgressView() } else { Text("Add to calendar").bold() }; Spacer() } }
                            .disabled(saving || chosenItem == nil)
                        if let t = target {
                            Button("More options (repeat weekly, rotations…)") { onOpenFull(t) }
                        }
                    }
                }
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving)
    }

    private var currentKind: AppModule { kind ?? kinds.first ?? .kids }
    private var chosenItem: Item? { let list = items[currentKind] ?? []; return list.first { $0.id == itemId } ?? list.first }
    private var target: ScheduleTarget? {
        guard let it = chosenItem else { return nil }
        switch currentKind {
        case .slides: return .deck(id: it.id, name: it.name)
        case .kids: return .playlist(id: it.id, name: it.name, kind: .kids)
        case .signage: return .playlist(id: it.id, name: it.name, kind: .signage)
        }
    }

    private func pickDefaults() {
        if currentKind == .signage { if screens.isEmpty, laneScreens.count == 1 { screens = [laneScreens[0].id] } }
        else if rooms.isEmpty, roomsFor(currentKind).count == 1 { rooms = [roomsFor(currentKind)[0].id] }
    }

    private func load() async {
        let org = model.church.id
        let svc = model.service
        var out: [AppModule: [Item]] = [:]
        if model.church.modules.contains(.kids) { out[.kids] = ((try? await svc.listPlaylists(kind: .kids, organizationId: org)) ?? []).map { Item(id: $0.id, name: $0.name) } }
        if model.church.modules.contains(.signage) { out[.signage] = ((try? await svc.listPlaylists(kind: .signage, organizationId: org)) ?? []).map { Item(id: $0.id, name: $0.name) } }
        if model.church.modules.contains(.slides) { out[.slides] = ((try? await svc.listDecks(organizationId: org)) ?? []).map { Item(id: $0.id, name: $0.name) } }
        items = out
        loading = false
        // Rooms: when the lane is one room (or only one fits) it is already ticked.
        for m in AppModule.allCases where m != .signage && rooms.isEmpty && roomsFor(m).count == 1 { rooms = [roomsFor(m)[0].id] }
        if let s = laneScreens.first, laneScreens.count == 1 { screens = [s.id] }
    }

    private func save() async {
        guard let target, let it = chosenItem else { return }
        errorText = nil
        saving = true
        defer { saving = false }
        do {
            let org = model.church.id
            let rows: [NewScheduleRow]
            if currentKind == .signage {
                var f = SignageForm()
                if case .group = request.lane.lane, let g = request.lane.groupIds.first { f.targets = [.group(g)] }
                else { f.targets = laneScreens.filter { screens.contains($0.id) }.map { .screen($0.id) } }
                f.weekdays = [day.weekday]; f.start = startTime; f.end = endTime
                rows = try ScheduleRowBuilder.slotRows(playlistId: it.id, form: f, organizationId: org, existing: [])
            } else {
                var f = ScheduleForm(day: day, start: startTime, hasEnd: true, end: endTime, weekdays: [day.weekday], startDate: day, endDate: day.adding(days: 84), rotation: [it.id])
                f.mode = .once
                f.locationIds = rooms
                rows = try ScheduleRowBuilder.rows(target: target, form: f, organizationId: org, orderedLocations: directory.locations.map(\.id), timeZone: { directory.timeZone(forLocation: $0) })
            }
            guard !rows.isEmpty else { throw ChurchError(currentKind == .signage ? "Choose a screen." : "Choose at least one location.") }
            try await model.service.createSchedules(rows, organizationId: org)
            dismiss()
        } catch {
            errorText = Formatting.message(for: error)
        }
    }
}
