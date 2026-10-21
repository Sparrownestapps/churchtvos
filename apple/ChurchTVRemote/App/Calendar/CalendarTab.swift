import SwiftUI
import ChurchTVCore
import ChurchTVCalendar

// The native calendar inside the Remote app (iPhone: second segment of the Today tab, iPad: "Calendar" in the sidebar).
// The calendar package never opens editors: tapping a block opens the existing ScheduleSheet, dragging out a time opens a small
// "Add" sheet (CalendarQuickAdd.swift) that writes through the same Core row builders as the ScheduleSheet.

/// Test launch arguments (DEBUG): `-calendar` opens the calendar first, `-calmode day|3day|week`, `-caldate 2026-10-21`,
/// `-callane <part of a location or screen name>`, `-calquickadd`, `-caldetail`.
enum CalendarLaunch {
    static var args: [String] {
        #if DEBUG
        return CommandLine.arguments
        #else
        return []
        #endif
    }
    static var opensCalendar: Bool { args.contains("-calendar") }
    static func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    static var mode: CalendarModel.Mode {
        switch value("-calmode") {
        case "day": return .day
        case "3day": return .threeDay
        case "week": return .week
        default: return Self.isPhone ? .day : .week
        }
    }
    static var day: CalendarDay? { value("-caldate").flatMap { CalendarDay(string: $0) } }
    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
}

/// iPhone: the Today tab holds "Today" (the old read-only list) and "Calendar".
struct TodayCalendarTab: View {
    @Environment(AppModel.self) private var app
    private enum Part: String, CaseIterable { case today = "Today", calendar = "Calendar" }
    @State private var part: Part = CalendarLaunch.opensCalendar ? .calendar : .today

    private var hasCalendar: Bool { !(app.church?.modules.isEmpty ?? true) }

    var body: some View {
        Group {
            switch part {
            case .today: TodayView()
            case .calendar: CalendarTab()
            }
        }
        .toolbar {
            if hasCalendar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $part) { ForEach(Part.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 200)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The calendar for the current church. Everyone with a live module sees it; operators see it read-only (events are locked, no "+").
struct CalendarTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let church = app.church, !church.modules.isEmpty {
            CalendarContent(church: church, service: app.service).id(church.id)
        } else {
            ContentUnavailableView("No calendar yet", systemImage: "calendar", description: Text("The calendar appears once your church has Kids, Slides or Signage."))
        }
    }
}

private struct CalendarContent: View {
    @State private var model: CalendarModel
    @State private var scheduleTarget: ScheduleTarget?
    @State private var detail: CalendarEvent?
    @State private var create: CalendarCreateRequest?

    init(church: ChurchAccess, service: any ChurchService) {
        _model = State(initialValue: CalendarModel(service: service, church: church, mode: CalendarLaunch.mode, anchor: CalendarLaunch.day))
    }

    var body: some View {
        ChurchCalendarView(model: model, callbacks: CalendarCallbacks(onSelect: select, onCreate: { create = $0 }))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $scheduleTarget, onDismiss: reload) { ScheduleSheet(target: $0) }
            .sheet(item: $detail) { e in CalendarEventDetail(event: e, model: model) { target in detail = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scheduleTarget = target } } }
            .sheet(item: $create, onDismiss: reload) { req in
                CalendarQuickAdd(request: req, model: model, onOpenFull: { target in create = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scheduleTarget = target } })
            }
            .task { await debugSetup() }
    }

    private func reload() { Task { await model.reload() } }

    /// Editors open the existing ScheduleSheet for the item; everyone else (and module switches) gets a read-only detail sheet.
    private func select(_ e: CalendarEvent) {
        if e.editable, let target = e.scheduleTarget(names: model.source?.names ?? [:]) { scheduleTarget = target } else { detail = e }
    }

    private func debugSetup() async {
        #if DEBUG
        guard CalendarLaunch.args.contains("-demo") else { return }
        while model.source == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        if let part = CalendarLaunch.value("-callane")?.lowercased(), let o = model.laneOptions.first(where: { $0.title.lowercased().contains(part) && $0.lane != .all }) { model.lane = o.lane }
        if CalendarLaunch.args.contains("-calquickadd") { create = model.createRequest(day: model.visibleDays[min(2, model.visibleDays.count - 1)], startMinute: 9 * 60 + 30, endMinute: 11 * 60) }
        if CalendarLaunch.args.contains("-caldetail") {
            try? await Task.sleep(nanoseconds: 600_000_000)
            detail = model.events.first { $0.style == .kidsRepeating }
        }
        #endif
    }
}


extension CalendarEvent {
    /// The deck or playlist this block plays (what the ScheduleSheet needs). Module switches have none.
    func scheduleTarget(names: [UUID: String]) -> ScheduleTarget? {
        func name(_ id: UUID) -> String { names[id] ?? title }
        switch source {
        case .oneOff(let module, _, let s, _): return target(module, s.itemId, name(s.itemId))
        case .occurrence(let module, _, let series, let occ):
            guard let id = occ.itemId ?? series.itemIds.first else { return nil }
            return target(module, id, name(id))
        case .slot(let slot): return .playlist(id: slot.playlistId, name: name(slot.playlistId), kind: .signage)
        case .moduleRule: return nil
        }
    }
    private func target(_ module: AppModule, _ id: UUID, _ name: String) -> ScheduleTarget {
        module == .slides ? .deck(id: id, name: name) : .playlist(id: id, name: name, kind: module == .signage ? .signage : .kids)
    }
}

// MARK: - Read-only detail

struct CalendarEventDetail: View {
    let event: CalendarEvent
    let model: CalendarModel
    let onEdit: (ScheduleTarget) -> Void
    @Environment(\.dismiss) private var dismiss

    private var tz: TimeZone { model.timeZone }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(event.title).font(.headline)
                    LabeledContent("Starts", value: ScheduleText.when(event.start, in: tz))
                    LabeledContent("Ends", value: ScheduleText.when(event.end, in: tz))
                    if let loc = event.locationId { LabeledContent("Where", value: model.directory.locationName(loc)) }
                    if let sub = event.subtitle { LabeledContent("Details", value: sub) }
                }
                Section {
                    switch event.source {
                    case .occurrence(_, _, let s, _):
                        Label("Repeats \(ScheduleDays.label(s.days)), \(ScheduleText.timeRange(s.startTime, s.endTime))", systemImage: "repeat")
                    case .slot(let s):
                        Label("Weekly: \(ScheduleDays.label(s.days)), \(ScheduleText.timeRange(s.startTime, s.endTime, endOfDay: s.endIsEndOfDay))", systemImage: "repeat")
                    case .moduleRule(let r):
                        Label("Weekly: \(ScheduleDays.label(r.days)), \(ScheduleText.timeRange(r.startTime, r.endTime, endOfDay: r.endIsEndOfDay))", systemImage: "repeat")
                    case .oneOff: Label("One time", systemImage: "calendar")
                    }
                    if let why = event.lockReason { Label(why, systemImage: "lock.fill").foregroundStyle(.secondary) }
                    if case .moduleRule = event.source, event.editable {
                        Label("Module switches are edited on the website.", systemImage: "safari").foregroundStyle(.secondary)
                    }
                }
                if !event.editable, let t = event.scheduleTarget(names: model.source?.names ?? [:]), ContentPermissions.canEditRole(model.church.role) {
                    Section { Button("Open schedule anyway") { onEdit(t) } } footer: { Text("The server decides whether you may change it.") }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
