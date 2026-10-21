import SwiftUI
import ChurchTVCore

/// The calendar: toolbar (previous / today / next, date picker, Day / 3 days / Week, location filter, add), the legend and the time grid.
/// Own the `CalendarModel` in the host (so it can call `reload()` after an editor saved) and pass callbacks for tap and create.
public struct ChurchCalendarView: View {
    @Bindable var model: CalendarModel
    let callbacks: CalendarCallbacks
    @State private var showDatePicker = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(model: CalendarModel, callbacks: CalendarCallbacks) {
        self.model = model; self.callbacks = callbacks
    }

    private var modes: [CalendarModel.Mode] {
        // Seven columns do not fit a phone in portrait.
        #if os(iOS)
        sizeClass == .compact ? [.day, .threeDay] : CalendarModel.Mode.allCases
        #else
        CalendarModel.Mode.allCases
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            infoBar
            Divider()
            if let e = model.loadError, model.source == nil {
                ContentUnavailableView {
                    Label("Couldn't load the calendar", systemImage: "calendar.badge.exclamationmark")
                } description: { Text(e) } actions: {
                    Button("Try again") { Task { await model.reload() } }.buttonStyle(.borderedProminent)
                }
            } else if model.source == nil {
                ProgressView("Loading calendar…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TimeGridView(model: model, callbacks: callbacks)
                    .overlay(alignment: .top) { if model.isBusy { ProgressView().padding(8).background(.regularMaterial, in: Capsule()).padding(.top, 70) } }
            }
        }
        .task { await model.reload() }
        .onChange(of: sizeClass) { _, _ in if !modes.contains(model.mode) { model.mode = modes.last ?? .day } }
        .background(shortcuts)
        .alert("Couldn't change that", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.actionError ?? "") }
        .confirmationDialog(model.pendingEdit?.title ?? "", isPresented: Binding(get: { model.pendingEdit != nil }, set: { if !$0 { model.pendingEdit = nil } }),
                            titleVisibility: .visible, presenting: model.pendingEdit) { edit in
            ForEach(edit.choices) { c in
                Button(c.label) { Task { await model.run(c.change) } }
            }
            Button("Open details instead") { callbacks.onSelect(edit.event) }
            Button("Cancel", role: .cancel) {}
        } message: { edit in
            Text(([edit.message] + edit.choices.compactMap { c in c.hint.map { "\(c.label): \($0)" } }).joined(separator: "\n\n"))
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Button { model.goPrevious() } label: { Image(systemName: "chevron.left").frame(minWidth: 32, minHeight: 32) }.accessibilityLabel("Previous")
                    Button("Today") { model.goToday() }.buttonStyle(.bordered).controlSize(.small).fixedSize()
                    Button { model.goNext() } label: { Image(systemName: "chevron.right").frame(minWidth: 32, minHeight: 32) }.accessibilityLabel("Next")
                }
                Button { showDatePicker = true } label: {
                    Text(model.title).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                    Image(systemName: "calendar").font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose date, \(model.title)")
                .popover(isPresented: $showDatePicker) { datePicker.presentationCompactAdaptation(.popover) }
                Spacer(minLength: 0)
                laneMenu
                if model.canCreate {
                    Button {
                        callbacks.onCreate(defaultCreate())
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Add to the calendar")
                }
            }
            Picker("View", selection: $model.mode) {
                ForEach(modes) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var datePicker: some View {
        let b = Binding<Date>(
            get: { SiteClock.wallDate(day: model.anchor, time: ClockTime(12)) },
            set: { model.go(to: SiteClock.wallParts($0).day); showDatePicker = false })
        return DatePicker("Date", selection: b, displayedComponents: .date)
            .datePickerStyle(.graphical).labelsHidden()
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .padding(8).frame(minWidth: 300, minHeight: 320)
    }

    private var laneMenu: some View {
        Menu {
            let options = model.laneOptions
            Picker("Show", selection: $model.lane) {
                ForEach(Array(Set(options.map(\.group))).sorted { a, b in
                    (options.firstIndex { $0.group == a } ?? 0) < (options.firstIndex { $0.group == b } ?? 0) }, id: \.self) { group in
                    Section(group) {
                        ForEach(options.filter { $0.group == group }) { Text($0.title).tag($0.lane) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(model.resolvedLane.label).lineLimit(1).font(.subheadline)
            }
            .frame(maxWidth: 120)
        }
        .accessibilityLabel("Filter by location or screen, now \(model.resolvedLane.label)")
    }

    private func defaultCreate() -> CalendarCreateRequest {
        let tz = model.timeZone
        let now = WallTime(Date(), in: tz)
        let day = model.visibleDays.contains(now.day) ? now.day : (model.visibleDays.first ?? now.day)
        let start = day == now.day ? min(CalendarGeometry().snap(now.minutes, rule: .up), 22 * 60) : 9 * 60
        return model.createRequest(day: day, startMinute: start, endMinute: start + 60)
    }

    // MARK: Legend

    private var infoBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(model.timeZoneNote).lineLimit(2)
            }
            .font(.caption2).foregroundStyle(model.timeZoneDiffers ? Color.orange : .secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(legendStyles, id: \.self) { s in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(CalendarPalette.of(s).background).overlay(RoundedRectangle(cornerRadius: 2).stroke(CalendarPalette.of(s).border)).frame(width: 12, height: 12)
                            Text(s.legend).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if model.isReadOnly { Label("View only", systemImage: "eye").font(.caption2).foregroundStyle(.secondary) }
                    if !model.warnings.isEmpty { Label(model.warnings[0], systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange) }
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private var legendStyles: [CalendarEventStyle] {
        var out: [CalendarEventStyle] = []
        let m = model.modules
        if m.contains(.kids) { out += [.kidsOneTime, .kidsRepeating] }
        if m.contains(.slides) { out += [.slidesOneTime, .slidesRepeating] }
        if m.contains(.signage) { out.append(.signage) }
        out.append(.moduleSwitch)
        return out
    }

    // MARK: Keyboard (Mac, and iPad with a keyboard)

    private var shortcuts: some View {
        Group {
            Button("Previous") { model.goPrevious() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next") { model.goNext() }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Today") { model.goToday() }.keyboardShortcut("t", modifiers: [])
            Button("Day") { model.mode = .day }.keyboardShortcut("1", modifiers: .command)
            Button("3 Days") { model.mode = .threeDay }.keyboardShortcut("2", modifiers: .command)
            Button("Week") { if modes.contains(.week) { model.mode = .week } }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
