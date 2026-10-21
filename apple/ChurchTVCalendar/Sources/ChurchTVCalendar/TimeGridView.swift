import SwiftUI
import ChurchTVCore

/// What is being dragged right now (shared by all columns so a block can move across days).
struct DragPreview: Equatable {
    enum Kind: Equatable { case create, move(String), resize(String) }
    var kind: Kind
    var day: CalendarDay
    var start: Int
    var end: Int
}

/// The scrolling time grid: hour labels, a light line every 15 minutes, a darker line every hour, day columns with blocks, the now indicator.
struct TimeGridView: View {
    @Bindable var model: CalendarModel
    let callbacks: CalendarCallbacks
    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var gutter: CGFloat = 46
    @State private var drag: DragPreview?
    @State private var didScroll = false
    @State private var didScrollToEvents = false
    @Environment(\.colorScheme) private var scheme

    private var geometry: CalendarGeometry { CalendarGeometry(hourHeight: hourHeight) }

    var body: some View {
        GeometryReader { proxy in
            let days = model.visibleDays
            let dayWidth = max((proxy.size.width - gutter) / CGFloat(max(days.count, 1)), 20)
            VStack(spacing: 0) {
                DayHeaderRow(model: model, gutter: gutter, dayWidth: dayWidth)
                Divider()
                ScrollViewReader { scroll in
                    ScrollView(.vertical) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) { ForEach(0..<24, id: \.self) { h in Color.clear.frame(width: 1, height: hourHeight).id("hour\(h)") } }.allowsHitTesting(false)
                            GridLines(geometry: geometry, gutter: gutter, dayCount: days.count, dayWidth: dayWidth)
                            ForEach(0..<24, id: \.self) { h in
                                Text(CalendarFormat.hourLabels[h])
                                    .font(.caption2).foregroundStyle(.secondary).dynamicTypeSize(.xSmall ... .xxxLarge)
                                    .frame(width: gutter - 6, alignment: .trailing)
                                    .offset(y: geometry.y(minute: h * 60) - 7).opacity(h == 0 ? 0 : 1)
                                    .accessibilityHidden(true)
                            }
                            HStack(spacing: 0) {
                                Color.clear.frame(width: gutter)
                                ForEach(days, id: \.self) { day in
                                    DayColumn(model: model, callbacks: callbacks, day: day, geometry: geometry, dayWidth: dayWidth, days: days, drag: $drag)
                                        .frame(width: dayWidth, height: geometry.totalHeight)
                                }
                            }
                            NowIndicator(model: model, geometry: geometry, gutter: gutter, dayWidth: dayWidth)
                        }
                        .frame(width: proxy.size.width, height: geometry.totalHeight, alignment: .topLeading)
                    }
                    .scrollDisabled(drag != nil)
                    .scrollIndicators(.visible)
                    .refreshable { await model.reload() }
                    .onAppear {
                        guard !didScroll else { return }
                        didScroll = true
                        Task { try? await Task.sleep(nanoseconds: 300_000_000); scroll.scrollTo("hour\(model.initialScrollHour)", anchor: .top) }
                    }
                    .onChange(of: model.events.count) { _, n in
                        if n > 0, !didScrollToEvents { didScrollToEvents = true; Task { try? await Task.sleep(nanoseconds: 150_000_000); scroll.scrollTo("hour\(model.initialScrollHour)", anchor: .top) } }
                    }
                    .onChange(of: model.scrollNonce) { _, _ in scroll.scrollTo("hour\(model.initialScrollHour)", anchor: .top) }
                }
            }
        }
    }
}

extension CalendarModel {
    /// Where the grid first scrolls: an hour before the earliest block of the visible days (7 AM at the earliest), or 7 AM.
    var initialScrollHour: Int {
        let first = placed.values.flatMap { $0 }.map { $0.segment.startMinute }.filter { $0 > 0 }.min() ?? 7 * 60
        return max(0, min(first / 60 - 1, 7))
    }
    var scrollNonce: Int { visibleDays.first.map { $0.year * 10_000 + $0.month * 100 + $0.day } ?? 0 }
}

struct GridLines: View {
    let geometry: CalendarGeometry
    let gutter: CGFloat
    let dayCount: Int
    let dayWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let steps = 24 * 60 / geometry.snapMinutes
            for i in 0...steps {
                let minute = i * geometry.snapMinutes
                let y = geometry.y(minute: minute)
                var line = Path()
                line.move(to: CGPoint(x: gutter - 4, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                if minute % 60 == 0 {
                    ctx.stroke(line, with: .color(.primary.opacity(0.30)), lineWidth: 1)         // darker line at every hour
                } else {
                    ctx.stroke(line, with: .color(.primary.opacity(0.09)), lineWidth: 0.5)       // light line every 15 minutes
                }
            }
            for d in 0...dayCount {
                var v = Path()
                let x = gutter + CGFloat(d) * dayWidth
                v.move(to: CGPoint(x: x, y: 0)); v.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(v, with: .color(.primary.opacity(0.14)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DayHeaderRow: View {
    @Bindable var model: CalendarModel
    let gutter: CGFloat
    let dayWidth: CGFloat

    private static let weekday: DateFormatter = { let f = DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: 0); f.setLocalizedDateFormatFromTemplate("EEE"); return f }()
    private static let long: DateFormatter = { let f = DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: 0); f.setLocalizedDateFormatFromTemplate("EEEEMMMMd"); return f }()

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(model.visibleDays, id: \.self) { day in
                let isToday = day == model.today
                Button {
                    if model.mode != .day { model.mode = .day; model.go(to: day) }
                } label: {
                    VStack(spacing: 2) {
                        Text(Self.weekday.string(from: day.noonUTC).uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(isToday ? Color.accentColor : .secondary)
                        Text("\(day.day)").font(.title3.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(isToday ? Color.white : .primary)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(Circle().fill(isToday ? Color.accentColor : .clear))
                    }
                    .frame(width: dayWidth).padding(.vertical, 4)
                    .dynamicTypeSize(.xSmall ... .xxxLarge)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.long.string(from: day.noonUTC) + (isToday ? ", today" : ""))
                .accessibilityHint(model.mode == .day ? "" : "Shows this day")
            }
        }
    }
}

struct NowIndicator: View {
    let model: CalendarModel
    let geometry: CalendarGeometry
    let gutter: CGFloat
    let dayWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = WallTime(ctx.date, in: model.timeZone)
            if let i = model.visibleDays.firstIndex(of: now.day) {
                let y = geometry.y(minute: now.minutes)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.red).frame(width: dayWidth, height: 1.5)
                    Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: -4.5)
                }
                .offset(x: gutter + CGFloat(i) * dayWidth, y: y - 0.75)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - A day column

struct DayColumn: View {
    @Bindable var model: CalendarModel
    let callbacks: CalendarCallbacks
    let day: CalendarDay
    let geometry: CalendarGeometry
    let dayWidth: CGFloat
    let days: [CalendarDay]
    @Binding var drag: DragPreview?

    @State private var createAnchorY: CGFloat?

    private var segments: [PlacedSegment] { (model.placed[day] ?? []).sorted { $0.segment.startMinute < $1.segment.startMinute } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Which module a screen runs (screen / group views).
            ForEach(Array(model.bands.filter { $0.day == day }.enumerated()), id: \.offset) { _, b in
                Rectangle().fill(CalendarPalette.band(b.module))
                    .frame(height: geometry.y(minute: b.toMinute - b.fromMinute)).offset(y: geometry.y(minute: b.fromMinute))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            emptySpace
            ForEach(segments) { ps in
                EventSlot(model: model, callbacks: callbacks, placed: ps, geometry: geometry, dayWidth: dayWidth, days: days, drag: $drag)
            }
            if let d = drag, d.day == day { ghost(d) }
        }
        .accessibilityElement(children: .contain)
    }

    // Create: tap an empty time (an hour), press and hold then drag (iPhone/iPad), or just drag (Mac).
    @ViewBuilder private var emptySpace: some View {
        #if os(iOS)
        HoldDrag(
            onTap: { p in
                guard model.canCreate else { return }
                let r = geometry.createRange(fromY: p.y, toY: p.y)
                callbacks.onCreate(model.createRequest(day: day, startMinute: r.start, endMinute: r.end))
            },
            onChange: { s, c in if model.canCreate { updateCreate(startY: s.y, y: c.y) } },
            onEnd: { s, c in if model.canCreate { finishCreate(startY: s.y, y: c.y) } else { drag = nil } },
            onCancel: { drag = nil })
            .accessibilityHidden(true)
        #else
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                guard model.canCreate else { return }
                let r = geometry.createRange(fromY: p.y, toY: p.y)
                callbacks.onCreate(model.createRequest(day: day, startMinute: r.start, endMinute: r.end))
            }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .local)
                    .onChanged { v in if model.canCreate { updateCreate(startY: v.startLocation.y, y: v.location.y) } }
                    .onEnded { v in if model.canCreate { finishCreate(startY: v.startLocation.y, y: v.location.y) } else { drag = nil } })
            .accessibilityHidden(true)
        #endif
    }

    private func updateCreate(startY: CGFloat, y: CGFloat) {
        let r = geometry.createRange(fromY: startY, toY: y)
        drag = DragPreview(kind: .create, day: day, start: r.start, end: r.end)
    }
    private func finishCreate(startY: CGFloat, y: CGFloat) {
        let r = geometry.createRange(fromY: startY, toY: y)
        drag = nil
        callbacks.onCreate(model.createRequest(day: day, startMinute: r.start, endMinute: r.end))
    }

    @ViewBuilder private func ghost(_ d: DragPreview) -> some View {
        let f = geometry.frame(startMinute: d.start, endMinute: d.end)
        let label = CalendarFormat.range(d.start, d.end)
        switch d.kind {
        case .create:
            RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2))
                .frame(width: max(dayWidth - 4, 10), height: f.height).offset(x: 2, y: f.y).allowsHitTesting(false)
        case .move(let id), .resize(let id):
            if let e = model.events.first(where: { $0.id == id }) {
                EventBlockView(event: e, startMinute: d.start, endMinute: d.end, height: f.height, ghost: true)
                    .frame(width: max(dayWidth - 4, 10), height: f.height).offset(x: 2, y: f.y).allowsHitTesting(false)
            }
        }
        DragTimeLabel(text: label)
            .frame(width: dayWidth, alignment: .center)
            .offset(y: max(f.y - 26, 0)).allowsHitTesting(false)
    }
}

// MARK: - One block with its gestures

struct EventSlot: View {
    @Bindable var model: CalendarModel
    let callbacks: CalendarCallbacks
    let placed: PlacedSegment
    let geometry: CalendarGeometry
    let dayWidth: CGFloat
    let days: [CalendarDay]
    @Binding var drag: DragPreview?

    private var event: CalendarEvent { placed.event }
    private var seg: CalendarSegment { placed.segment }
    private var singleDay: Bool { !seg.continuesBefore && !seg.continuesAfter }
    private var canDrag: Bool { event.editable && singleDay && !model.isBusy }
    private var canResize: Bool { canDrag && event.canResize }
    private var isDragged: Bool {
        guard let d = drag else { return false }
        switch d.kind { case .move(let id), .resize(let id): return id == event.id; case .create: return false }
    }

    var body: some View {
        let f = geometry.frame(startMinute: seg.startMinute, endMinute: seg.endMinute)
        let cols = max(placed.placement.columnCount, 1)
        let colWidth = (dayWidth - 4) / CGFloat(cols)
        let width = max(colWidth - 1, 8)
        EventBlockView(event: event, startMinute: seg.startMinute, endMinute: seg.endMinute, height: f.height, dimmed: isDragged)
            .frame(width: width, height: f.height)
            .overlay { interaction }
            .overlay(alignment: .bottom) { if canResize { resizeHandle(width: width) } }
            .offset(x: 2 + colWidth * CGFloat(placed.placement.column), y: f.y)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(event.editable ? "Double tap to open." : (event.lockReason ?? "View only."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open") { callbacks.onSelect(event) }
            .modifier(NudgeActions(enabled: canDrag, canResize: canResize, model: model, event: event))
    }

    private var accessibilityText: String {
        var parts = [event.title, "\(CalendarFormat.time(seg.startMinute)) to \(CalendarFormat.time(seg.endMinute))"]
        if event.isRepeating { parts.append("repeating") }
        if let s = event.subtitle { parts.append(s) }
        if !event.editable { parts.append("view only") }
        return parts.joined(separator: ", ")
    }

    private func resizeHandle(width: CGFloat) -> some View {
        Capsule().fill(Color.primary.opacity(0.35)).frame(width: min(28, width * 0.6), height: 4)
            .padding(.bottom, 2)
            .frame(width: width, height: 22, alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { v in
                        let r = geometry.resized(startMinute: seg.startMinute, endMinute: seg.endMinute, translationY: v.translation.height)
                        drag = DragPreview(kind: .resize(event.id), day: seg.day, start: r.start, end: r.end)
                    }
                    .onEnded { v in
                        let r = geometry.resized(startMinute: seg.startMinute, endMinute: seg.endMinute, translationY: v.translation.height)
                        drag = nil
                        persist(day: seg.day, start: r.start, end: r.end)
                    }
            )
            .accessibilityHidden(true)
    }

    private func target(_ translation: CGSize) -> (day: CalendarDay, start: Int, end: Int) {
        let shift = days.contains(seg.day) ? Int((translation.width / dayWidth).rounded()) : 0
        let idx = min(max((days.firstIndex(of: seg.day) ?? 0) + shift, 0), days.count - 1)
        let m = geometry.moved(startMinute: seg.startMinute, endMinute: seg.endMinute, translationY: translation.height)
        return (days[idx], m.start, m.end)
    }

    private func updateMove(_ translation: CGSize) {
        let t = target(translation)
        drag = DragPreview(kind: .move(event.id), day: t.day, start: t.start, end: t.end)
    }
    private func finishMove(_ translation: CGSize) {
        let t = target(translation)
        drag = nil
        persist(day: t.day, start: t.start, end: t.end)
    }
    private func persist(day: CalendarDay, start: Int, end: Int) {
        let e = event
        Task { await model.commit(e, newStart: WallTime(day: day, minutes: start), newEnd: WallTime(day: day, minutes: end)) }
    }

    /// Tap opens; moving needs a press-and-hold first on iPhone/iPad (so scrolling still works) and a plain drag on the Mac.
    @ViewBuilder private var interaction: some View {
        #if os(iOS)
        HoldDrag(dragEnabled: canDrag, onTap: { _ in callbacks.onSelect(event) },
                 onChange: { s, c in updateMove(CGSize(width: c.x - s.x, height: c.y - s.y)) },
                 onEnd: { s, c in finishMove(CGSize(width: c.x - s.x, height: c.y - s.y)) },
                 onCancel: { drag = nil })
        #else
        Color.clear.contentShape(Rectangle())
            .onTapGesture { callbacks.onSelect(event) }
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { v in if canDrag { updateMove(v.translation) } }
                    .onEnded { v in if canDrag { finishMove(v.translation) } else { drag = nil } },
                including: canDrag ? .all : .subviews)
        #endif
    }
}

/// VoiceOver: move and resize in 15 minute steps without dragging.
struct NudgeActions: ViewModifier {
    let enabled: Bool
    let canResize: Bool
    let model: CalendarModel
    let event: CalendarEvent

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if enabled {
                Button("Move 15 minutes later") { Task { await model.nudge(event, moveMinutes: 15) } }
                Button("Move 15 minutes earlier") { Task { await model.nudge(event, moveMinutes: -15) } }
                if canResize {
                    Button("Make 15 minutes longer") { Task { await model.nudge(event, resizeMinutes: 15) } }
                    Button("Make 15 minutes shorter") { Task { await model.nudge(event, resizeMinutes: -15) } }
                }
            }
        }
    }
}
