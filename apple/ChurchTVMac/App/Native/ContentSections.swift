import SwiftUI
import AppKit
import ChurchTVCore
import ChurchTVEditors
import ChurchTVCalendar

// Content: the editors package (Kids playlists, Signage playlists, Slides decks, Themes), the native calendar, and the Mac host for both.

/// The Mac app is the editors' host: it supplies the session, the TVs and "Play now" (through the remote command protocol).
extension MenuModel: ContentHost {
    var supportsPlayNow: Bool { true }

    func playNowView(_ target: PlayNowTarget) -> AnyView? { AnyView(EditorPlayNow(target: target).environment(self)) }
}

/// One sidebar entry of the Create group: the editors' list pinned to Kids, Signage, Slides decks or Themes.
struct CreateSectionView: View {
    let section: AppSection
    var body: some View {
        CreateRoot(initialSection: section.rawValue)
    }
}

// MARK: - Calendar

/// The native calendar (ChurchTVCalendar). Tapping a block opens the real ScheduleSheet; "+" or dragging out a time asks what to schedule, then opens the ScheduleSheet.
struct CalendarSection: View {
    @Environment(MenuModel.self) private var model
    @State private var calendar: CalendarModel?
    @State private var scheduleTarget: ScheduleTarget?
    @State private var detail: CalendarEvent?
    @State private var create: CalendarCreateRequest?

    var body: some View {
        Group {
            if let church = model.church, let calendar {
                ChurchCalendarView(model: calendar, callbacks: CalendarCallbacks(onSelect: { select($0, calendar) }, onCreate: { create = $0 }))
                    .id(church.id)
            } else { ProgressView() }
        }
        .sheet(item: $scheduleTarget, onDismiss: { Task { await calendar?.reload() } }) { ScheduleSheet(target: $0) }
        .sheet(item: $detail) { e in if let calendar { CalendarDetailSheet(event: e, model: calendar) { t in detail = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scheduleTarget = t } } } }
        .sheet(item: $create) { req in
            CalendarCreatePicker(request: req) { t in create = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scheduleTarget = t } }
        }
        .task {
            guard calendar == nil, let church = model.church else { return }
            calendar = CalendarModel(service: model.service, church: church, mode: Self.launchMode, anchor: Self.launchDay)
        }
        .task(id: calendar != nil) { await debugSetup() }
    }

    private func select(_ e: CalendarEvent, _ calendar: CalendarModel) {
        if e.editable, let t = e.scheduleTarget(names: calendar.source?.names ?? [:]) { scheduleTarget = t } else { detail = e }
    }

    // Debug launch arguments (with -demo): -calmode day|3day|week  -caldate 2026-10-25  -callane <part of a name>  -calcreate
    private static func arg(_ k: String) -> String? { CommandLine.arguments.firstIndex(of: k).flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } }
    private static var launchMode: CalendarModel.Mode { switch arg("-calmode") { case "day": return .day; case "3day": return .threeDay; default: return .week } }
    private static var launchDay: CalendarDay? { arg("-caldate").flatMap { CalendarDay(string: $0) } }

    private func debugSetup() async {
        #if DEBUG
        guard let calendar, CommandLine.arguments.contains("-demo") else { return }
        while calendar.source == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        if let part = Self.arg("-callane")?.lowercased(), let o = calendar.laneOptions.first(where: { $0.title.lowercased().contains(part) && $0.lane != .all }) { calendar.lane = o.lane }
        if CommandLine.arguments.contains("-calcreate") { create = calendar.createRequest(day: calendar.visibleDays[min(2, calendar.visibleDays.count - 1)], startMinute: 9 * 60 + 30, endMinute: 11 * 60) }
        #endif
    }
}

extension CalendarEvent {
    /// The deck or playlist this block plays (what the ScheduleSheet needs). Module switches have none.
    func scheduleTarget(names: [UUID: String]) -> ScheduleTarget? {
        func name(_ id: UUID) -> String { names[id] ?? title }
        func target(_ module: AppModule, _ id: UUID) -> ScheduleTarget {
            module == .slides ? .deck(id: id, name: name(id)) : .playlist(id: id, name: name(id), kind: module == .signage ? .signage : .kids)
        }
        switch source {
        case .oneOff(let module, _, let s, _): return target(module, s.itemId)
        case .occurrence(let module, _, let series, let occ):
            guard let id = occ.itemId ?? series.itemIds.first else { return nil }
            return target(module, id)
        case .slot(let slot): return .playlist(id: slot.playlistId, name: name(slot.playlistId), kind: .signage)
        case .moduleRule: return nil
        }
    }
}

/// Read-only details of a block (locked blocks and module switches).
private struct CalendarDetailSheet: View {
    let event: CalendarEvent
    let model: CalendarModel
    let onEdit: (ScheduleTarget) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title).font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow { Text("Starts").foregroundStyle(.secondary); Text(ScheduleText.when(event.start, in: model.timeZone)) }
                GridRow { Text("Ends").foregroundStyle(.secondary); Text(ScheduleText.when(event.end, in: model.timeZone)) }
                if let loc = event.locationId { GridRow { Text("Where").foregroundStyle(.secondary); Text(model.directory.locationName(loc)) } }
                if let sub = event.subtitle { GridRow { Text("Details").foregroundStyle(.secondary); Text(sub) } }
            }
            if let why = event.lockReason { Label(why, systemImage: "lock.fill").foregroundStyle(.secondary) }
            if case .moduleRule = event.source { Label("Module switches are edited on the website.", systemImage: "safari").foregroundStyle(.secondary) }
            HStack {
                if !event.editable, let t = event.scheduleTarget(names: model.source?.names ?? [:]), ContentPermissions.canEditRole(model.church.role) {
                    Button("Open schedule anyway") { onEdit(t) }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 420)
    }
}

/// "+" in the calendar: choose the deck or playlist to schedule, then the ScheduleSheet sets the room and the time.
private struct CalendarCreatePicker: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: CalendarCreateRequest
    let onPick: (ScheduleTarget) -> Void
    @State private var items: [PlayNowItem] = []
    @State private var signage: [Playlist] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you want to schedule?").font(.title3.weight(.semibold))
            Text("\(request.day) \(Self.hm(request.startMinute)) to \(Self.hm(request.endMinute)). You choose the room and the time on the next screen.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                let decks = items.filter { $0.kind == .deck }, lists = items.filter { $0.kind == .playlist }
                if !decks.isEmpty { Section("Slides decks") { ForEach(decks) { i in row(i.name, "play.rectangle.on.rectangle") { .deck(id: i.refId, name: i.name) } } } }
                if !lists.isEmpty { Section("Kids playlists") { ForEach(lists) { i in row(i.name, "figure.and.child.holdinghands") { .playlist(id: i.refId, name: i.name, kind: .kids) } } } }
                if !signage.isEmpty { Section("Signage playlists") { ForEach(signage) { p in row(p.name, "rectangle.on.rectangle") { .playlist(id: p.id, name: p.name, kind: .signage) } } } }
            }
            .frame(minHeight: 240)
            .overlay { if loaded && items.isEmpty && signage.isEmpty { Text("Create a deck or playlist first.").foregroundStyle(.secondary) } else if !loaded { ProgressView() } }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 460, height: 460)
        .task {
            guard let church = model.church else { return }
            let editable = Set(church.editableModules)
            items = ((try? await model.service.playNowItems(organizationId: church.id, modules: church.modules)) ?? []).filter { editable.contains($0.module) }
            if editable.contains(.signage) { signage = (try? await model.service.listPlaylists(kind: .signage, organizationId: church.id)) ?? [] }
            loaded = true
        }
    }

    private static func hm(_ m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }

    private func row(_ name: String, _ icon: String, _ target: @escaping () -> ScheduleTarget) -> some View {
        Button { onPick(target()) } label: { Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}

// MARK: - Website fallback

/// Sections that are not native yet open the website here (its own sign-in, kept by the web view).
struct WebFallbackSection: View {
    @Environment(MenuModel.self) private var model
    let section: AppSection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                Text("\(section.title) is shown from the website until it is built natively. Sign in there if asked.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Open in browser") { NSWorkspace.shared.open(URL(string: AppLinks.dashboard.absoluteString + "#" + (section.webRoute ?? ""))!) }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
            Divider()
            MainWindowView()
        }
        .onAppear { model.web.openRoute(section.webRoute ?? "") }
    }
}
