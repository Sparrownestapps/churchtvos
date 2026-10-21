import XCTest
import ChurchTVCore
@testable import ChurchTVCalendar

final class CalendarGeometryTests: XCTestCase {
    let g = CalendarGeometry(hourHeight: 60)   // 1 point per minute keeps the arithmetic readable

    func testTimeToYAndBack() {
        XCTAssertEqual(g.y(minute: 0), 0)
        XCTAssertEqual(g.y(minute: 9 * 60 + 30), 570)
        XCTAssertEqual(g.totalHeight, 1440)
        XCTAssertEqual(g.minute(y: 570), 570)
        XCTAssertEqual(g.minute(y: -20), 0); XCTAssertEqual(g.minute(y: 5000), 1440)
        let tall = CalendarGeometry(hourHeight: 80)
        XCTAssertEqual(tall.y(minute: 90), 120, accuracy: 0.001)
        XCTAssertEqual(tall.minute(y: tall.y(minute: 437.0)), 437, accuracy: 0.001)
    }

    func testSnappingToFifteenMinutes() {
        XCTAssertEqual(g.snap(7.4), 0); XCTAssertEqual(g.snap(7.5), 15); XCTAssertEqual(g.snap(22.0), 15)
        XCTAssertEqual(g.snap(29.0, rule: .down), 15); XCTAssertEqual(g.snap(31.0, rule: .up), 45)
        XCTAssertEqual(g.snap(1439.0), 1440); XCTAssertEqual(g.snap(-5.0), 0); XCTAssertEqual(g.snap(2000.0), 1440)
    }

    func testCreateRangeDraggedDownUpAndTapped() {
        XCTAssertTrue(g.createRange(fromY: 541, toY: 640) == (540, 645))             // down: start floors, end ceils
        XCTAssertTrue(g.createRange(fromY: 640, toY: 541) == (540, 645))             // up: same range
        XCTAssertTrue(g.createRange(fromY: 600, toY: 603) == (600, 615))             // tiny drag: one step
        XCTAssertTrue(g.createRange(fromY: 548, toY: 548) == (540, 600))             // a tap: an hour at the slot
        XCTAssertTrue(g.createRange(fromY: 1430, toY: 1440) == (1425, 1440))         // near midnight stays inside the day
        XCTAssertTrue(g.createRange(fromY: 1438, toY: 1438) == (1425, 1440))
    }

    func testMoveKeepsLengthSnapsAndStaysInsideTheDay() {
        XCTAssertEqual(g.moved(startMinute: 540, endMinute: 600, translationY: 22).start, 555)      // 22 min -> 15
        XCTAssertEqual(g.moved(startMinute: 540, endMinute: 600, translationY: 23).start, 570)
        XCTAssertEqual(g.moved(startMinute: 540, endMinute: 600, translationY: 38).start, 585)      // 38 -> 45
        XCTAssertEqual(g.moved(startMinute: 540, endMinute: 600, translationY: -22).start, 525)
        let top = g.moved(startMinute: 30, endMinute: 90, translationY: -500)
        XCTAssertEqual(top.start, 0); XCTAssertEqual(top.end, 60)
        let bottom = g.moved(startMinute: 1300, endMinute: 1400, translationY: 900)
        XCTAssertEqual(bottom.end, 1440); XCTAssertEqual(bottom.start, 1340)
    }

    func testResizeFollowsTheBottomEdge() {
        XCTAssertEqual(g.resized(startMinute: 540, endMinute: 600, translationY: 40).end, 645)      // 40 -> 45
        XCTAssertEqual(g.resized(startMinute: 540, endMinute: 600, translationY: -200).end, 555)    // never shorter than a step
        XCTAssertEqual(g.resized(startMinute: 540, endMinute: 600, translationY: 9999).end, 1440)
        XCTAssertEqual(g.resized(startMinute: 540, endMinute: 600, translationY: 40).start, 540)
    }

    func testMinimumBlockHeightAndDayColumnIndex() {
        XCTAssertEqual(g.frame(startMinute: 600, endMinute: 600).height, 15)
        XCTAssertEqual(g.frame(startMinute: 600, endMinute: 660).height, 60)
        XCTAssertEqual(CalendarGeometry.dayIndex(x: 0, dayWidth: 100, count: 7), 0)
        XCTAssertEqual(CalendarGeometry.dayIndex(x: 250, dayWidth: 100, count: 7), 2)
        XCTAssertEqual(CalendarGeometry.dayIndex(x: 9999, dayWidth: 100, count: 7), 6)
        XCTAssertEqual(CalendarGeometry.dayIndex(x: -50, dayWidth: 100, count: 7), 0)
    }

    // MARK: Overlap columns

    func cols(_ r: [(Int, Int)]) -> [[Int]] { g.columns(for: r.map { (start: $0.0, end: $0.1) }).map { [$0.column, $0.columnCount] } }

    func testNoOverlapUsesTheFullWidth() {
        XCTAssertEqual(cols([(540, 600), (600, 660), (700, 760)]), [[0, 1], [0, 1], [0, 1]])   // touching blocks do not overlap
    }
    func testTwoOverlappingShareTheWidth() {
        XCTAssertEqual(cols([(540, 660), (600, 720)]), [[0, 2], [1, 2]])
    }
    func testThreeWayAndReuseOfFreeColumn() {
        // A 9-12, B 9:30-10, C 10-11 (fits under B in column 1), D 10:30-11:30 (needs column 2 because A and C are busy).
        let r = cols([(540, 720), (570, 600), (600, 660), (630, 690)])
        XCTAssertEqual(r[0], [0, 3]); XCTAssertEqual(r[1], [1, 3]); XCTAssertEqual(r[2], [1, 3]); XCTAssertEqual(r[3], [2, 3])
    }
    func testChainOfOverlapsIsOneClusterAndSeparateClustersAreIndependent() {
        let r = cols([(540, 600), (590, 650), (640, 700), (900, 960)])
        XCTAssertEqual(r[0], [0, 2]); XCTAssertEqual(r[1], [1, 2]); XCTAssertEqual(r[2], [0, 2]); XCTAssertEqual(r[3], [0, 1])
    }
    func testZeroLengthBlocksStillOccupyMinimumRoom() {
        XCTAssertEqual(cols([(600, 600), (605, 660)]), [[0, 2], [1, 2]])
    }
    func testInputOrderDoesNotMatter() {
        XCTAssertEqual(cols([(600, 720), (540, 660)]), [[1, 2], [0, 2]])
    }
}

// Tuples are not Equatable.
func == (a: (start: Int, end: Int), b: (Int, Int)) -> Bool { a.start == b.0 && a.end == b.1 }
