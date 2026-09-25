import Foundation
import XCTest
@testable import SayoneCore

final class TodayListMergerTests: XCTestCase {
    private let cal = Fixtures.moscow
    private let now = Fixtures.date(2025, 9, 25, 14, 0, 0)
    private var day: DateInterval { TodayMath.day(containing: now, calendar: cal) }

    func testMergesLocalAndOtherDeviceRowsNewestFirst() {
        let saved = Fixtures.entry(date: now.addingTimeInterval(-3600), drinkName: "Вода", volumeML: 250, health: .saved)
        let pending = Fixtures.entry(date: now.addingTimeInterval(-60), drinkName: "Кофе", volumeML: 200,
                                     waterML: 200, health: .pending, origin: .phone)
        let otherID = UUID()
        let samples = [
            Fixtures.sample(date: saved.date, waterML: 250, entryID: saved.id),                    // own sample: not a row
            Fixtures.sample(date: now.addingTimeInterval(-1800), waterML: 330, entryID: otherID,
                            drinkName: "Кола без сахара", volumeML: 330, origin: .watch),
            Fixtures.sample(date: now.addingTimeInterval(-900), waterML: 400, entryID: nil)          // other app: not a row
        ]
        let rows = TodayListMerger.merge(local: [saved, pending], health: samples, day: day)
        XCTAssertEqual(rows.map(\.id), [pending.id, otherID, saved.id])

        XCTAssertEqual(rows[0], TodayRow(id: pending.id, date: pending.date, drinkName: "Кофе", symbol: "drop.fill",
                                         volumeML: 200, waterML: 200, origin: .phone, isLocal: true, isPendingHealth: true))
        XCTAssertEqual(rows[1], TodayRow(id: otherID, date: now.addingTimeInterval(-1800), drinkName: "Кола без сахара",
                                         symbol: nil, volumeML: 330, waterML: 330, origin: .watch, isLocal: false,
                                         isPendingHealth: false))
        XCTAssertTrue(rows[2].isLocal)
        XCTAssertFalse(rows[2].isPendingHealth)
        XCTAssertEqual(rows[2].symbol, "drop.fill")
    }

    func testHiddenLocalEntriesAndTheirSamplesAreNotRows() {
        let deleting = Fixtures.entry(date: now.addingTimeInterval(-600), health: .pendingDelete)
        let deleted = Fixtures.entry(date: now.addingTimeInterval(-500), health: .deleted)
        let samples = [
            Fixtures.sample(date: deleting.date, waterML: 250, entryID: deleting.id),
            Fixtures.sample(date: deleted.date, waterML: 250, entryID: deleted.id)
        ]
        XCTAssertEqual(TodayListMerger.merge(local: [deleting, deleted], health: samples, day: day), [])
    }

    func testOutOfDayItemsAreExcluded() {
        let yesterday = Fixtures.entry(date: Fixtures.date(2025, 9, 24, 23, 59, 59))
        let tomorrowMidnight = Fixtures.sample(date: Fixtures.date(2025, 9, 26), waterML: 100, entryID: UUID())
        let yesterdaySample = Fixtures.sample(date: Fixtures.date(2025, 9, 24, 12), waterML: 100, entryID: UUID())
        XCTAssertEqual(TodayListMerger.merge(local: [yesterday], health: [tomorrowMidnight, yesterdaySample], day: day), [])
    }

    func testOtherDeviceFallbacks() {
        let id = UUID()
        let sample = Fixtures.sample(date: now, waterML: 237.6, entryID: id, drinkName: nil, volumeML: nil, origin: nil)
        let rows = TodayListMerger.merge(local: [], health: [sample, sample], day: day)
        XCTAssertEqual(rows.count, 1, "duplicate samples for one entry give one row")
        XCTAssertEqual(rows[0].drinkName, Phrasebook.genericDrink(AppLanguage.bundleDefault))
        XCTAssertEqual(rows[0].volumeML, 238)
        XCTAssertNil(rows[0].symbol)
        XCTAssertNil(rows[0].origin)
        XCTAssertFalse(rows[0].isLocal)
    }
}
