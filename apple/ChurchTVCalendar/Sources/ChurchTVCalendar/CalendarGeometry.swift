import Foundation
import CoreGraphics
import ChurchTVCore

/// Pure layout math of the time grid (no SwiftUI): time <-> y, snapping to 15 minutes, side-by-side columns for overlapping blocks
/// and what a drag means. Unit tested.
public struct CalendarGeometry: Equatable, Sendable {
    public var hourHeight: CGFloat
    public var snapMinutes: Int
    /// Blocks shorter than this still get this much height / overlap room.
    public var minDisplayMinutes: Int

    public init(hourHeight: CGFloat = 56, snapMinutes: Int = 15, minDisplayMinutes: Int = 15) {
        self.hourHeight = hourHeight; self.snapMinutes = snapMinutes; self.minDisplayMinutes = minDisplayMinutes
    }

    public static let minutesPerDay = 1440
    public var totalHeight: CGFloat { hourHeight * 24 }
    public var pointsPerMinute: CGFloat { hourHeight / 60 }

    /// y of a minute after midnight.
    public func y(minute: Double) -> CGFloat { CGFloat(minute) * pointsPerMinute }
    public func y(minute: Int) -> CGFloat { y(minute: Double(minute)) }
    /// Minute after midnight at y (not snapped, clamped to the day).
    public func minute(y: CGFloat) -> Double { min(max(Double(y / pointsPerMinute), 0), Double(Self.minutesPerDay)) }

    /// Snaps to the grid: nearest by default. Result is within 0...1440.
    public func snap(_ minute: Double, rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        let step = Double(snapMinutes)
        let v = (minute / step).rounded(rule) * step
        return Int(min(max(v, 0), Double(Self.minutesPerDay)))
    }
    public func snap(_ minute: Int, rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int { snap(Double(minute), rule: rule) }

    /// Vertical extent of a block, with the minimum height.
    public func frame(startMinute: Int, endMinute: Int) -> (y: CGFloat, height: CGFloat) {
        let end = max(endMinute, startMinute + minDisplayMinutes)
        return (y(minute: startMinute), y(minute: end - startMinute))
    }

    // MARK: Day columns

    /// Index of the column at x (clamped), for `count` columns of `dayWidth`.
    public static func dayIndex(x: CGFloat, dayWidth: CGFloat, count: Int) -> Int {
        guard dayWidth > 0, count > 0 else { return 0 }
        return min(max(Int((x / dayWidth).rounded(.down)), 0), count - 1)
    }

    // MARK: Drags

    /// A range dragged out on empty space: from where the press started to where it is now (either direction), snapped, at least one step,
    /// kept inside the day. A press without movement (`to == from`) gives `defaultMinutes` (an hour, like the website's click).
    public func createRange(fromY: CGFloat, toY: CGFloat, defaultMinutes: Int = 60) -> (start: Int, end: Int) {
        let a = minute(y: fromY), b = minute(y: toY)
        if abs(fromY - toY) < 1 {
            let s = min(snap(a, rule: .down), Self.minutesPerDay - snapMinutes)
            return (s, min(s + defaultMinutes, Self.minutesPerDay))
        }
        var s = snap(min(a, b), rule: .down)
        var e = snap(max(a, b), rule: .up)
        if e - s < snapMinutes { e = s + snapMinutes }
        if e > Self.minutesPerDay { e = Self.minutesPerDay; s = max(0, e - snapMinutes) }
        return (s, e)
    }

    /// Moving a block: the same length, shifted by the vertical drag (snapped) and by whole days sideways. Stays inside the day.
    public func moved(startMinute: Int, endMinute: Int, translationY: CGFloat, dayShift: Int = 0) -> (start: Int, end: Int, dayShift: Int) {
        let length = endMinute - startMinute
        let delta = snap(Double(translationY / pointsPerMinute), rule: .toNearestOrAwayFromZero, signed: true)
        let s = min(max(startMinute + delta, 0), max(Self.minutesPerDay - length, 0))
        return (s, s + length, dayShift)
    }

    /// Resizing by the bottom edge: the end follows the drag (snapped), at least one step after the start, at most midnight.
    public func resized(startMinute: Int, endMinute: Int, translationY: CGFloat) -> (start: Int, end: Int) {
        let delta = snap(Double(translationY / pointsPerMinute), rule: .toNearestOrAwayFromZero, signed: true)
        let e = min(max(endMinute + delta, startMinute + snapMinutes), Self.minutesPerDay)
        return (startMinute, e)
    }

    /// Snap a signed delta in minutes (rounds half away from zero).
    func snap(_ minutes: Double, rule: FloatingPointRoundingRule, signed: Bool) -> Int {
        let step = Double(snapMinutes)
        return Int((minutes / step).rounded(rule) * step)
    }

    // MARK: Overlap columns

    public struct Placement: Equatable, Sendable {
        public var column: Int
        public var columnCount: Int
        public init(column: Int, columnCount: Int) { self.column = column; self.columnCount = columnCount }
    }

    /// Side-by-side columns for the blocks of ONE day. Blocks that overlap (also through a chain of overlaps) share a cluster; each
    /// takes the first free column and the cluster's width is split by its widest moment. Keyed by segment index in `segments`.
    public func columns(for segments: [(start: Int, end: Int)]) -> [Placement] {
        let order = segments.indices.sorted { a, b in
            segments[a].start != segments[b].start ? segments[a].start < segments[b].start : (segments[a].end != segments[b].end ? segments[a].end > segments[b].end : a < b)
        }
        func end(_ i: Int) -> Int { max(segments[i].end, segments[i].start + minDisplayMinutes) }
        var result = [Placement](repeating: Placement(column: 0, columnCount: 1), count: segments.count)
        var cluster: [Int] = []
        var columnEnds: [Int] = []
        var clusterEnd = Int.min
        func flush() {
            for i in cluster { result[i].columnCount = max(columnEnds.count, 1) }
            cluster = []; columnEnds = []; clusterEnd = .min
        }
        for i in order {
            if !cluster.isEmpty, segments[i].start >= clusterEnd { flush() }
            var col = columnEnds.firstIndex { $0 <= segments[i].start }
            if col == nil { columnEnds.append(0); col = columnEnds.count - 1 }
            columnEnds[col!] = end(i)
            result[i].column = col!
            cluster.append(i)
            clusterEnd = max(clusterEnd, end(i))
        }
        flush()
        return result
    }
}
