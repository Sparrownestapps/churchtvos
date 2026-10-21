import SwiftUI
import ChurchTVCore

// MARK: - Where (Kids, Slides)

struct LocationSection: View {
    let vm: ScheduleSheetModel

    var body: some View {
        if vm.isLoading && vm.candidateLocations.isEmpty {
            Section("Where") { HStack { ProgressView(); Text("Loading locations…").foregroundStyle(.secondary) } }
        } else if vm.candidateLocations.isEmpty {
            Section {
                Banner(text: vm.module == .slides
                       ? "No locations are tagged for Slides (or Kids) yet. Tag a room under Sites & Locations on the website."
                       : "No locations are tagged for Kids yet. Tag a room under Sites & Locations on the website.", style: .warning)
            } header: { Text("Where") }
        } else {
            ForEach(vm.locationGroups) { group in
                Section {
                    ForEach(group.locations) { loc in
                        Button {
                            if vm.form.locationIds.contains(loc.id) { vm.form.locationIds.remove(loc.id) } else { vm.form.locationIds.insert(loc.id) }
                            Haptics.selection()
                        } label: {
                            HStack {
                                Text(loc.name).foregroundStyle(.primary)
                                if vm.isKidsOnlyRoom(loc) { Text("Kids").font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()).foregroundStyle(.secondary) }
                                Spacer()
                                Image(systemName: vm.form.locationIds.contains(loc.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(vm.form.locationIds.contains(loc.id) ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(loc.name + (vm.isKidsOnlyRoom(loc) ? ", Kids room" : ""))
                        .accessibilityAddTraits(vm.form.locationIds.contains(loc.id) ? .isSelected : [])
                    }
                } header: {
                    HStack {
                        Text(vm.locationGroups.count > 1 ? "Where · \(group.site?.name ?? "No site")" : "Where")
                        Spacer()
                        Button(allOn(group.locations) ? "None" : "All") { setAll(group.locations, on: !allOn(group.locations)) }
                            .font(.footnote).textCase(nil).buttonStyle(.borderless)
                    }
                } footer: {
                    if group.id == vm.locationGroups.last?.id, vm.module == .slides {
                        Text(vm.taggedSlidesCount == 0 ? "No rooms are tagged for Slides yet, so Kids rooms are listed too (marked Kids)." : "Rooms tagged Slides are listed, and so are Kids rooms (marked Kids).")
                    }
                }
            }
        }
    }

    private func allOn(_ list: [Location]) -> Bool { list.allSatisfy { vm.form.locationIds.contains($0.id) } }
    private func setAll(_ list: [Location], on: Bool) {
        for l in list { if on { vm.form.locationIds.insert(l.id) } else { vm.form.locationIds.remove(l.id) } }
    }
}

// MARK: - When (Kids, Slides)

private let utc = TimeZone(secondsFromGMT: 0)!

/// Date and time pickers that edit wall-clock values (no device time zone involved).
func dayBinding(_ get: @escaping () -> CalendarDay, _ set: @escaping (CalendarDay) -> Void) -> Binding<Date> {
    Binding(get: { SiteClock.wallDate(day: get(), time: ClockTime(12)) }, set: { set(SiteClock.wallParts($0).day) })
}
func timeBinding(_ get: @escaping () -> ClockTime, _ set: @escaping (ClockTime) -> Void) -> Binding<Date> {
    Binding(get: { SiteClock.wallDate(day: CalendarDay(year: 2026, month: 1, day: 1), time: get()) }, set: { set(SiteClock.wallParts($0).time) })
}

struct WallDatePicker: View {
    let title: String
    let selection: Binding<Date>
    let components: DatePickerComponents
    var body: some View {
        DatePicker(title, selection: selection, displayedComponents: components).environment(\.timeZone, utc)
    }
}

struct WhenSection: View {
    @Bindable var vm: ScheduleSheetModel

    var body: some View {
        Section {
            Picker("Schedule", selection: $vm.form.mode) {
                Text("Just once").tag(ScheduleForm.Mode.once)
                Text("Repeat every week").tag(ScheduleForm.Mode.repeating)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("How often")

            if vm.form.mode == .once {
                WallDatePicker(title: "Date", selection: dayBinding({ vm.form.day }, { vm.form.day = $0 }), components: .date)
                WallDatePicker(title: "Starts", selection: timeBinding({ vm.form.start }, { vm.form.start = $0 }), components: .hourAndMinute)
                Toggle("Set an end time", isOn: $vm.form.hasEnd)
                if vm.form.hasEnd {
                    WallDatePicker(title: "Ends", selection: timeBinding({ vm.form.end }, { vm.form.end = $0 }), components: .hourAndMinute)
                } else {
                    Text("With no end time it plays until the next schedule starts.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Days").font(.subheadline).foregroundStyle(.secondary)
                    DayChips(days: $vm.form.weekdays)
                }
                WallDatePicker(title: "From", selection: timeBinding({ vm.form.start }, { vm.form.start = $0 }), components: .hourAndMinute)
                WallDatePicker(title: "Until", selection: timeBinding({ vm.form.end }, { vm.form.end = $0 }), components: .hourAndMinute)
                WallDatePicker(title: "Starts on", selection: dayBinding({ vm.form.startDate }, { vm.form.startDate = $0 }), components: .date)
                Toggle("Ends on a date", isOn: $vm.form.hasEndDate)
                if vm.form.hasEndDate {
                    WallDatePicker(title: "Last day", selection: dayBinding({ vm.form.endDate }, { vm.form.endDate = $0 }), components: .date)
                }
                TextField("Name (optional)", text: $vm.form.name)
            }
            TimeZoneNote(zones: vm.activeZones)
        } header: { Text("When") }
    }
}

/// Shows the time zone the times are in; orange when it differs from the phone's.
struct TimeZoneNote: View {
    let zones: [TimeZone]
    var body: some View {
        let differs = zones.contains { SiteClock.differsFromDevice($0) }
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(zones.isEmpty ? "Times are in the church's time zone." : "Time zone: " + zones.map(SiteClock.displayName).joined(separator: " and "))
                    .font(.footnote.weight(differs ? .semibold : .regular))
            } icon: { Image(systemName: differs ? "exclamationmark.triangle.fill" : "clock").foregroundStyle(differs ? .orange : .secondary) }
            if differs {
                Text("Your phone is set to \(SiteClock.displayName(.current)). The times above are in the church's time zone, not yours.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        .listRowBackground(differs ? Color.orange.opacity(0.14) : nil)
        .accessibilityElement(children: .combine)
    }
}

struct DayChips: View {
    @Binding var days: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 8)], spacing: 8) {
                ForEach(0..<7, id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        if on { days.remove(d) } else { days.insert(d) }
                        Haptics.selection()
                    } label: {
                        Text(ScheduleDays.shortNames[d])
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ScheduleDays.fullNames[d])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack(spacing: 16) {
                Button("Every day") { days = ScheduleDays.everyDay }
                Button("Weekdays") { days = ScheduleDays.weekdays }
                Button("Weekend") { days = ScheduleDays.weekend }
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Rotation

struct RotationSection: View {
    @Bindable var vm: ScheduleSheetModel
    @Binding var editMode: EditMode

    var body: some View {
        Section {
            ForEach(Array(vm.form.rotation.enumerated()), id: \.offset) { index, _ in
                Picker("Week \(index + 1)", selection: Binding(get: { vm.form.rotation[safe: index] ?? vm.target.id }, set: { if index < vm.form.rotation.count { vm.form.rotation[index] = $0 } })) {
                    ForEach(choices(including: vm.form.rotation[safe: index])) { Text($0.name).tag($0.id) }
                }
                .accessibilityLabel("Week \(index + 1)")
            }
            .onDelete { offsets in if vm.form.rotation.count > offsets.count { vm.form.rotation.remove(atOffsets: offsets) } }
            .onMove { vm.form.rotation.move(fromOffsets: $0, toOffset: $1) }

            Button { vm.form.rotation.append(vm.form.rotation.last ?? vm.target.id) } label: { Label("Add another week", systemImage: "plus.circle") }
            if vm.form.rotation.count > 1 {
                Picker("When it reaches the end", selection: $vm.form.onEnd) {
                    Text("Start over").tag(OnEnd.loop)
                    Text("Stop").tag(OnEnd.stop)
                }
            }
        } header: {
            HStack {
                Text("Rotation")
                Spacer()
                if vm.form.rotation.count > 1 {
                    Button(editMode == .active ? "Done" : "Reorder") { editMode = editMode == .active ? .inactive : .active }
                        .font(.footnote).textCase(nil).buttonStyle(.borderless)
                }
            }
        } footer: {
            Text(vm.form.rotation.count > 1
                 ? "Each date plays the next item in the list. A skipped date does not use up a week, so the rotation waits."
                 : "The same item plays every week. Add more weeks to rotate through several \(vm.module == .slides ? "decks" : "playlists").")
        }
    }

    struct Choice: Identifiable { let id: UUID; let name: String }
    private func choices(including id: UUID?) -> [Choice] {
        var list = vm.rotationChoices.map { Choice(id: $0.id, name: $0.name) }
        if let id, !list.contains(where: { $0.id == id }) { list.append(Choice(id: id, name: vm.itemName(id))) }
        return list
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Signage

struct SignageWhereSection: View {
    let vm: ScheduleSheetModel

    var body: some View {
        Section {
            if vm.signageNeedsAllSites {
                Banner(text: "Signage slots apply to the whole church, so only editors with access to all sites can change them. You can try, but the server may refuse.", style: .warning)
            }
            if vm.isLoading && vm.app.screens.isEmpty {
                HStack { ProgressView(); Text("Loading screens…").foregroundStyle(.secondary) }
            }
            if vm.app.screens.isEmpty && !vm.isLoading && vm.groups.isEmpty {
                Text("No screens yet.").foregroundStyle(.secondary)
            }
        } header: { Text("Where") }
        if !vm.groups.isEmpty {
            Section("Screen groups") {
                ForEach(vm.groups) { g in row(.group(g.id), title: g.name, subtitle: "Every screen in the group", symbol: "rectangle.3.group") }
            }
        }
        if !vm.app.screens.isEmpty {
            Section("Screens") {
                ForEach(vm.app.screens) { s in row(.screen(s.id), title: s.screen.displayName, subtitle: s.locationLine, symbol: "tv") }
            }
        }
    }

    private func row(_ t: SignageTargetRef, title: String, subtitle: String, symbol: String) -> some View {
        let on = vm.signage.targets.contains(t)
        return Button { vm.toggle(t); Haptics.selection() } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.primary)
                        if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                } icon: { Image(systemName: symbol).foregroundStyle(.secondary) }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (subtitle.isEmpty ? "" : ", " + subtitle))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct SignageWhenSection: View {
    @Bindable var vm: ScheduleSheetModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Days").font(.subheadline).foregroundStyle(.secondary)
                DayChips(days: $vm.signage.weekdays)
            }
            WallDatePicker(title: "From", selection: timeBinding({ vm.signage.start }, { vm.signage.start = $0 }), components: .hourAndMinute)
            WallDatePicker(title: "Until", selection: timeBinding({ vm.signage.end }, { vm.signage.end = $0 }), components: .hourAndMinute)
            Toggle("Higher priority than overlapping rules", isOn: $vm.signage.higherPriority)
            TimeZoneNote(zones: vm.activeZones)
        } header: { Text("When") } footer: {
            Text("Slots repeat every week. When slots overlap, the highest priority plays. With the switch on, this slot gets one more than the highest priority the screen or group already has. 11:59 PM means the end of the day.")
        }
    }
}
