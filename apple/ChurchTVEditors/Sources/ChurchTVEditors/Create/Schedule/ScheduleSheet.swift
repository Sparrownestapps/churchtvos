import SwiftUI
import ChurchTVCore

/// Schedules a deck, Kids playlist or Signage playlist: where, when, a hint about overlaps, and the list of what is already
/// scheduled for this item (with delete and "Skip next date"). Presented from the Create list and the Play now sheet.
public struct ScheduleSheet: View {
    @Environment(ContentModel.self) private var model
    let target: ScheduleTarget

    public init(target: ScheduleTarget) { self.target = target }

    public var body: some View {
        ScheduleSheetBody(vm: ScheduleSheetModel(target: target, app: model))
    }
}

private struct ScheduleSheetBody: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ScheduleSheetModel
    @State private var editMode: EditMode = .inactive

    init(vm: ScheduleSheetModel) { _vm = State(initialValue: vm) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.target.name).font(.headline)
                            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: vm.module.symbol).foregroundStyle(.tint) }
                    .accessibilityElement(children: .combine)
                }

                if vm.isSignage {
                    SignageWhereSection(vm: vm)
                    SignageWhenSection(vm: vm).id("when")
                } else {
                    LocationSection(vm: vm)
                    WhenSection(vm: vm).id("when")
                    if vm.form.mode == .repeating { RotationSection(vm: vm, editMode: $editMode) }
                }

                if !vm.hints.isEmpty {
                    Section {
                        ForEach(Array(vm.hints.enumerated()), id: \.offset) { _, h in
                            Label { Text(h).font(.footnote) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                                .accessibilityElement(children: .combine)
                        }
                    } header: { Text("Heads up") } footer: { Text("You can still schedule it. This is only a reminder.") }
                }

                Section {
                    if let e = vm.errorText { Banner(text: e, style: .error) }
                    if let s = vm.successText { Banner(text: s, style: .info, systemImage: "checkmark.circle.fill") }
                    Button { Task { await vm.submit() } } label: {
                        HStack {
                            Spacer()
                            if vm.isSaving { ProgressView() } else { Text(vm.isSignage ? "Add slot" : vm.form.mode == .once ? "Schedule" : "Add repeating schedule").bold() }
                            Spacer()
                        }
                    }
                    .disabled(vm.problem != nil || vm.isSaving)
                } footer: {
                    if let p = vm.problem { Text(p) }
                }

                UpcomingSection(vm: vm).id("upcoming")
            }
            .task {
                #if DEBUG
                // Test launch argument `-schedscroll when|upcoming` scrolls the form (screenshots).
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-schedscroll"), i + 1 < args.count {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation { proxy.scrollTo(args[i + 1] == "upcoming" ? "upcoming" : "when", anchor: .top) }
                }
                #endif
            }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Schedule")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(vm.successText == nil ? "Close" : "Done") { dismiss() }.cancelShortcut() } }
            .task { await vm.load() }
            .interactiveDismissDisabled(vm.isSaving)
            .alert("Delete the whole repeating schedule?", isPresented: Binding(get: { vm.seriesToDelete != nil }, set: { if !$0 { vm.seriesToDelete = nil } }), presenting: vm.seriesToDelete) { s in
                Button("Delete", role: .destructive) { if let row = vm.upcoming.first(where: { $0.id == s.id }) { Task { await vm.delete(row) } } }
                Button("Cancel", role: .cancel) {}
            } message: { s in
                Text("Every \(ScheduleDays.label(s.days)) at \(vm.locationName(s.locationId)). All its dates and skipped dates are removed. This cannot be undone.")
            }
        }
        .presentationDetents([.large])
        .macSheetFrame(minWidth: 560, minHeight: 640)
    }

    private var subtitle: String {
        switch vm.target {
        case .deck: return "Slides deck"
        case .playlist(_, _, let kind): return kind.title
        }
    }
}
