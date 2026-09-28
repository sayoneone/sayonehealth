import Foundation
import XCTest
@testable import SayoneCore

final class WidgetTimelineTests: XCTestCase {
    private let cal = Fixtures.moscow

    func testRefreshInterval() {
        XCTAssertEqual(WidgetTimeline.refreshInterval, 1800)
    }

    func testDefaultIsThirtyMinutes() {
        let now = Fixtures.date(2025, 9, 25, 14, 0, 0)
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: nil, calendar: cal), now.addingTimeInterval(1800))
    }

    func testMidnightComesFirstLateInTheDay() {
        let now = Fixtures.date(2025, 9, 25, 23, 50, 0)
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: nil, calendar: cal), Fixtures.date(2025, 9, 26))
        let exactlyHalfHourBefore = Fixtures.date(2025, 9, 25, 23, 30, 0)
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: exactlyHalfHourBefore, undoUntil: nil, calendar: cal),
                       Fixtures.date(2025, 9, 26))
    }

    func testUndoExpiryComesFirstWhenSooner() {
        let now = Fixtures.date(2025, 9, 25, 14, 0, 0)
        let undo = now.addingTimeInterval(300)
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: undo, calendar: cal), undo)
    }

    func testUndoExpiryIgnoredWhenPastOrLater() {
        let now = Fixtures.date(2025, 9, 25, 14, 0, 0)
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: now, calendar: cal), now.addingTimeInterval(1800))
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: now.addingTimeInterval(-5), calendar: cal),
                       now.addingTimeInterval(1800))
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: now.addingTimeInterval(3600), calendar: cal),
                       now.addingTimeInterval(1800))
    }

    func testUndoBeforeMidnight() {
        let now = Fixtures.date(2025, 9, 25, 23, 58, 0)
        let undo = now.addingTimeInterval(60)
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: undo, calendar: cal), undo)
        XCTAssertEqual(WidgetTimeline.nextRefresh(after: now, undoUntil: now.addingTimeInterval(300), calendar: cal),
                       Fixtures.date(2025, 9, 26))
    }
}
