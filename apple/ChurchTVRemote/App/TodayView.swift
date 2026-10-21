import SwiftUI
import ChurchTVCore

/// Read-only schedule overview for today, per screen.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.screens.isEmpty {
                ContentUnavailableView("No screens", systemImage: "calendar", description: Text("Screens appear here once a TV is paired."))
            }
            ForEach(model.screens) { info in
                Section {
                    let entries = model.schedule.filter { $0.screenId == info.id }
                    if entries.isEmpty {
                        Text(model.scheduleLoaded ? "Nothing scheduled today" : "Loading…").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { e in EntryRow(entry: e, timeZone: info.timeZone) }
                } header: {
                    HStack(spacing: 6) {
                        OnlineDot(online: info.isOnline())
                        Text(info.screen.displayName)
                        if !info.locationLine.isEmpty { Text("· \(info.locationLine)").foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                Link(destination: Config.websiteURL) { Label("Edit schedules on the website", systemImage: "safari") }
            } footer: { Text("Schedules are read-only in the app.") }
        }
        .navigationTitle("Today")
        .task { await model.loadSchedule() }
        .refreshable { await model.loadSchedule() }
    }
}

struct EntryRow: View {
    let entry: ScheduleEntry
    let timeZone: TimeZone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.module.symbol).foregroundStyle(.tint).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.headline)
                HStack(spacing: 6) {
                    Text(timeText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    if entry.source == .repeating { Label("Repeats", systemImage: "repeat").font(.caption).foregroundStyle(.secondary) }
                    if entry.source == .moduleRule { Text("Module rule").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.timeStyle = .short
        f.dateStyle = .none
        let start = f.string(from: entry.starts)
        guard let end = entry.ends else { return "From \(start)" }
        return "\(start) – \(f.string(from: end))"
    }
}
