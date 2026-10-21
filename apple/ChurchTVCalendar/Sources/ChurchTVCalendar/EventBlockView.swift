import SwiftUI
import ChurchTVCore

enum CalendarFormat {
    /// "9:15 AM" for minutes after midnight (1440 reads as 12:00 AM).
    static func time(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        return ScheduleText.time(ClockTime(m / 60, m % 60))
    }
    static func range(_ a: Int, _ b: Int) -> String { "\(time(a)) – \(time(b))" }

    static let hourLabels: [String] = (0..<24).map { h in
        let f = DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: SiteClock.wallDate(day: CalendarDay(year: 2026, month: 1, day: 1), time: ClockTime(h)))
    }
}

/// One block on the grid (also used for the drag ghost).
struct EventBlockView: View {
    let event: CalendarEvent
    let startMinute: Int
    let endMinute: Int
    var height: CGFloat
    var dimmed = false
    var ghost = false

    var body: some View {
        let p = CalendarPalette.of(event.style)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(p.background)
            if !event.editable { HatchOverlay().clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous)).opacity(0.5) }
            HStack(spacing: 0) {
                Rectangle().fill(p.border).frame(width: 3)
                Spacer(minLength: 0)
            }.clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if !event.editable { Image(systemName: "lock.fill").font(.system(size: 9)).accessibilityHidden(true) }
                    if event.isRepeating { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .bold)).accessibilityHidden(true) }
                    Text(event.title).font(.caption.weight(.semibold)).lineLimit(height > 46 ? 2 : 1)
                }
                if height > 30 { Text(CalendarFormat.range(startMinute, endMinute)).font(.caption2).opacity(0.85).lineLimit(1) }
                if height > 56, let sub = event.subtitle { Text(sub).font(.caption2).opacity(0.85).lineLimit(1) }
            }
            .foregroundStyle(p.foreground)
            .padding(.leading, 7).padding(.trailing, 3).padding(.top, 2)
            .dynamicTypeSize(.xSmall ... .xxxLarge)
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(p.border.opacity(ghost ? 1 : 0.55), lineWidth: ghost ? 2 : 1)
        }
        .opacity(dimmed ? 0.35 : 1)
        .shadow(color: ghost ? .black.opacity(0.25) : .clear, radius: 6, y: 2)
        .contentShape(Rectangle())
    }
}

struct HatchOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height)); path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 8
            }
            ctx.stroke(path, with: .color(.gray.opacity(0.35)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The floating label shown while dragging ("9:15 AM – 10:30 AM").
struct DragTimeLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor))
            .foregroundStyle(.white)
            .shadow(radius: 3, y: 1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
