import SwiftUI
import ChurchTVCore

/// "Upcoming for this item": its one-off schedules, repeating series (next dates from the server) or signage slots.
struct UpcomingSection: View {
    let vm: ScheduleSheetModel

    var body: some View {
        let rows = vm.upcoming
        Section {
            if let e = vm.upcomingError { Banner(text: e, style: .error) }
            if rows.isEmpty {
                Text(vm.isLoading ? "Loading…" : "Nothing is scheduled for this item yet.").foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Label {
                        Text(row.title).font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: row.kind == .series ? "repeat" : row.kind == .slot ? "rectangle.on.rectangle" : "calendar").foregroundStyle(.tint)
                    }
                    Text(row.detail).font(.footnote).foregroundStyle(.secondary)
                    if let n = row.next { Text(n).font(.footnote).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .trailing, allowsFullSwipe: row.kind != .series) {
                    Button(role: .destructive) {
                        if let s = row.series { vm.seriesToDelete = s } else { Task { await vm.delete(row) } }
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    if row.kind == .series, let label = row.skipLabel {
                        Button { Task { await vm.skipNext(row) } } label: { Label(label, systemImage: "forward.end") }.tint(.orange)
                    }
                }
                .contextMenu {
                    if row.kind == .series, let label = row.skipLabel {
                        Button { Task { await vm.skipNext(row) } } label: { Label(label, systemImage: "forward.end") }
                    }
                    Button(role: .destructive) {
                        if let s = row.series { vm.seriesToDelete = s } else { Task { await vm.delete(row) } }
                    } label: { Label(row.kind == .series ? "Delete repeating schedule" : "Delete", systemImage: "trash") }
                }
            }
        } header: { Text("Upcoming for this item") } footer: {
            if !rows.isEmpty { Text("Swipe to delete. On a repeating schedule, swipe right to skip the next date.") }
        }
    }
}
