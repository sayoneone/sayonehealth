import Foundation
import XCTest
@testable import SayoneCore

final class LogDedupeTests: XCTestCase {
    private let t0 = Fixtures.date(2025, 9, 25, 12, 0, 0)

    private func widget(_ offset: TimeInterval, drinkID: String = "water", volumeML: Int = 500,
                        health: HealthSyncStatus = .pending, source: LogSource = .widget) -> IntakeEntry {
        Fixtures.entry(date: t0.addingTimeInterval(offset), drinkID: drinkID, volumeML: volumeML, health: health, source: source)
    }

    func testWindowIsTwoSeconds() {
        XCTAssertEqual(LogDedupe.window, 2)
    }

    func testWidgetTapWithinWindowIsDuplicate() {
        let first = widget(0)
        XCTAssertEqual(LogDedupe.duplicate(of: widget(1), in: [first]), first)
        XCTAssertEqual(LogDedupe.duplicate(of: widget(-1), in: [first]), first)
        XCTAssertEqual(LogDedupe.duplicate(of: widget(2), in: [first]), first)
    }

    func testOutsideWindowIsNotDuplicate() {
        XCTAssertNil(LogDedupe.duplicate(of: widget(2.001), in: [widget(0)]))
        XCTAssertNil(LogDedupe.duplicate(of: widget(-3), in: [widget(0)]))
    }

    func testOnlyWidgetCandidatesAreDeduplicated() {
        for source in [LogSource.app, .siri, .deepLink] {
            XCTAssertNil(LogDedupe.duplicate(of: widget(1, source: source), in: [widget(0)]), "\(source)")
        }
    }

    func testOnlyWidgetEntriesCount() {
        XCTAssertNil(LogDedupe.duplicate(of: widget(1), in: [widget(0, source: .app)]))
        XCTAssertNil(LogDedupe.duplicate(of: widget(1), in: [widget(0, source: .siri)]))
    }

    func testDrinkAndVolumeMustMatch() {
        XCTAssertNil(LogDedupe.duplicate(of: widget(1, volumeML: 250), in: [widget(0)]))
        XCTAssertNil(LogDedupe.duplicate(of: widget(1, drinkID: "tea"), in: [widget(0)]))
    }

    func testHiddenEntriesAreIgnored() {
        XCTAssertNil(LogDedupe.duplicate(of: widget(1), in: [widget(0, health: .pendingDelete)]))
        XCTAssertNil(LogDedupe.duplicate(of: widget(1), in: [widget(0, health: .deleted)]))
        let saved = widget(0, health: .saved)
        XCTAssertEqual(LogDedupe.duplicate(of: widget(1), in: [saved]), saved)
    }

    func testSameIDIsNotItsOwnDuplicate() {
        let candidate = widget(0)
        XCTAssertNil(LogDedupe.duplicate(of: candidate, in: [candidate]))
    }

    func testClosestMatchWins() {
        let far = widget(-1.8)
        let near = widget(0.5)
        XCTAssertEqual(LogDedupe.duplicate(of: widget(1), in: [far, near]), near)
    }
}
