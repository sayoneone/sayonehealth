import Foundation
import XCTest
@testable import SayoneCore

final class UndoPolicyTests: XCTestCase {
    private let now = Fixtures.date(2025, 9, 25, 12, 0, 0)

    func testConstants() {
        XCTAssertEqual(UndoPolicy.widgetWindow, 600)
        XCTAssertEqual(UndoPolicy.voiceWindow, 10_800)
        XCTAssertEqual(UndoPolicy.toastDuration, 5)
    }

    func testNewestVisibleEntryInWindow() {
        let older = Fixtures.entry(date: now.addingTimeInterval(-300))
        let newer = Fixtures.entry(date: now.addingTimeInterval(-60), health: .saved)
        XCTAssertEqual(UndoPolicy.candidate(in: [newer, older], now: now, window: UndoPolicy.widgetWindow), newer)
        XCTAssertEqual(UndoPolicy.candidate(in: [older, newer], now: now, window: UndoPolicy.widgetWindow), newer)
    }

    func testHiddenEntriesAreSkipped() {
        let visible = Fixtures.entry(date: now.addingTimeInterval(-300))
        let deleting = Fixtures.entry(date: now.addingTimeInterval(-10), health: .pendingDelete)
        let deleted = Fixtures.entry(date: now.addingTimeInterval(-5), health: .deleted)
        XCTAssertEqual(UndoPolicy.candidate(in: [visible, deleting, deleted], now: now, window: 600), visible)
        XCTAssertNil(UndoPolicy.candidate(in: [deleting, deleted], now: now, window: 600))
    }

    func testWindowBoundaries() {
        let atEdge = Fixtures.entry(date: now.addingTimeInterval(-600))
        XCTAssertEqual(UndoPolicy.candidate(in: [atEdge], now: now, window: 600), atEdge)
        let justOutside = Fixtures.entry(date: now.addingTimeInterval(-600.5))
        XCTAssertNil(UndoPolicy.candidate(in: [justOutside], now: now, window: 600))
        let exactlyNow = Fixtures.entry(date: now)
        XCTAssertEqual(UndoPolicy.candidate(in: [exactlyNow], now: now, window: 600), exactlyNow)
    }

    func testFutureEntriesAreNotCandidates() {
        let past = Fixtures.entry(date: now.addingTimeInterval(-100))
        let future = Fixtures.entry(date: now.addingTimeInterval(30))
        XCTAssertEqual(UndoPolicy.candidate(in: [past, future], now: now, window: 600), past)
    }

    func testVoiceWindowReachesFurther() {
        let twoHoursAgo = Fixtures.entry(date: now.addingTimeInterval(-7200))
        XCTAssertNil(UndoPolicy.candidate(in: [twoHoursAgo], now: now, window: UndoPolicy.widgetWindow))
        XCTAssertEqual(UndoPolicy.candidate(in: [twoHoursAgo], now: now, window: UndoPolicy.voiceWindow), twoHoursAgo)
    }

    func testEmptyAndNegativeWindow() {
        XCTAssertNil(UndoPolicy.candidate(in: [], now: now, window: 600))
        XCTAssertNil(UndoPolicy.candidate(in: [Fixtures.entry(date: now)], now: now, window: -1))
    }
}
