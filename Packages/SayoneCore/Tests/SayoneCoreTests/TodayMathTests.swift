import Foundation
import XCTest
@testable import SayoneCore

/// The total rule (§5.1). All dates are Europe/Moscow wall-clock times.
final class TodayMathTests: XCTestCase {
    private let cal = Fixtures.moscow
    private let now = Fixtures.date(2025, 9, 25, 14, 0, 0)
    private var todayStart: Date { Fixtures.date(2025, 9, 25) }

    /// Mirrors TodayService: HealthKit query first, THEN list the journal ids, then summarize.
    private func total(samples: [HealthWaterSample], journal: [IntakeEntry], now: Date? = nil,
                       readAt: Date? = nil) -> TodaySummary {
        let now = now ?? self.now
        let snapshot = TodayMath.makeSnapshot(samples: samples, localEntryIDs: Set(journal.map(\.id)), now: now,
                                              readAt: readAt ?? now, calendar: cal)
        return TodayMath.summary(snapshot: snapshot, local: journal, goalML: 2000, now: now, calendar: cal)
    }

    // MARK: - Day helpers

    func testDayContainingIsMoscowCalendarDay() {
        let day = TodayMath.day(containing: now, calendar: cal)
        XCTAssertEqual(day.start, todayStart)
        XCTAssertEqual(day.end, Fixtures.date(2025, 9, 26))
        XCTAssertEqual(day.start.timeIntervalSince1970, 1_758_747_600)  // 2025-09-24T21:00:00Z
        XCTAssertEqual(TodayMath.nextDayStart(after: now, calendar: cal), Fixtures.date(2025, 9, 26))
        XCTAssertEqual(TodayMath.nextDayStart(after: todayStart, calendar: cal), Fixtures.date(2025, 9, 26))
        XCTAssertEqual(TodayMath.nextDayStart(after: Fixtures.date(2025, 9, 25, 23, 59, 59), calendar: cal),
                       Fixtures.date(2025, 9, 26))
    }

    // MARK: - Required cases 1–10

    /// 1. A saved local entry whose sample is in HealthKit is counted once.
    func testSavedLocalEntryWithSampleCountsOnce() {
        let e = Fixtures.entry(date: now.addingTimeInterval(-3600), volumeML: 250, health: .saved)
        let s = total(samples: [Fixtures.sample(date: e.date, waterML: 250, entryID: e.id)], journal: [e])
        XCTAssertEqual(s.waterML, 250)
        XCTAssertEqual(s.localWaterML, 250)
        XCTAssertEqual(s.externalWaterML, 0)
        XCTAssertEqual(s.otherDeviceWaterML, 0)
    }

    /// 2. A pending entry whose sample is already in HealthKit (killed before markSaved) is counted once.
    func testPendingEntryWithSampleAlreadyInHealthCountsOnce() {
        let e = Fixtures.entry(date: now.addingTimeInterval(-60), volumeML: 330, health: .pending)
        let s = total(samples: [Fixtures.sample(date: e.date, waterML: 330, entryID: e.id)], journal: [e])
        XCTAssertEqual(s.waterML, 330)
        XCTAssertEqual(s.pendingCount, 1)
    }

    /// 3. A pendingDelete entry with its sample still in HealthKit counts 0.
    func testPendingDeleteWithSampleCountsZero() {
        let e = Fixtures.entry(date: now.addingTimeInterval(-60), volumeML: 500, health: .pendingDelete)
        let s = total(samples: [Fixtures.sample(date: e.date, waterML: 500, entryID: e.id)], journal: [e])
        XCTAssertEqual(s.waterML, 0)
        XCTAssertNil(s.lastLocal)
        XCTAssertNil(s.undoAvailableUntil)
    }

    /// 4. A deleted tombstone, with a snapshot taken while the sample still existed, counts 0.
    func testDeletedTombstoneWithStaleSnapshotCountsZero() {
        let e = Fixtures.entry(date: now.addingTimeInterval(-3600), volumeML: 500, health: .saved)
        // The snapshot is taken while the entry was still saved and its sample existed.
        let snapshot = TodayMath.makeSnapshot(samples: [Fixtures.sample(date: e.date, waterML: 500, entryID: e.id)],
                                              localEntryIDs: [e.id], now: now.addingTimeInterval(-600),
                                              readAt: now.addingTimeInterval(-600), calendar: cal)
        // Later the user deletes it; the journal keeps the tombstone.
        var tombstone = e
        tombstone.health = .deleted
        tombstone.deletedAt = now.addingTimeInterval(-60)
        let s = TodayMath.summary(snapshot: snapshot, local: [tombstone], goalML: 2000, now: now, calendar: cal)
        XCTAssertEqual(s.waterML, 0)
        XCTAssertEqual(s.externalWaterML, 0)
    }

    /// 5. A sample from the other device (entryID not local) is counted and included in otherDeviceWaterML.
    func testOtherDeviceSampleIsCounted() {
        let mine = Fixtures.entry(date: now.addingTimeInterval(-7200), volumeML: 250, health: .saved)
        let samples = [
            Fixtures.sample(date: mine.date, waterML: 250, entryID: mine.id),
            Fixtures.sample(date: now.addingTimeInterval(-1800), waterML: 300, entryID: UUID(), origin: .watch)
        ]
        let s = total(samples: samples, journal: [mine])
        XCTAssertEqual(s.waterML, 550)
        XCTAssertEqual(s.externalWaterML, 300)
        XCTAssertEqual(s.otherDeviceWaterML, 300)
        XCTAssertEqual(s.localWaterML, 250)
    }

    /// A foreign entry whose water sample exists twice (re-save from another process) counts once.
    func testDuplicateForeignSamplesCountOnce() {
        let foreign = UUID()
        let at = now.addingTimeInterval(-1800)
        let samples = [
            Fixtures.sample(date: at, waterML: 300, entryID: foreign, origin: .watch),
            Fixtures.sample(date: at, waterML: 300, entryID: foreign, origin: .watch),
            Fixtures.sample(date: at, waterML: 200, entryID: nil),
            Fixtures.sample(date: at, waterML: 200, entryID: nil)
        ]
        let s = total(samples: samples, journal: [])
        XCTAssertEqual(s.otherDeviceWaterML, 300)
        XCTAssertEqual(s.externalWaterML, 700)   // other apps' samples are never deduplicated
        XCTAssertEqual(s.waterML, 700)
    }

    /// 6. A sample from another app (entryID == nil) is counted.
    func testOtherAppSampleIsCounted() {
        let s = total(samples: [Fixtures.sample(date: now.addingTimeInterval(-60), waterML: 400, entryID: nil)], journal: [])
        XCTAssertEqual(s.waterML, 400)
        XCTAssertEqual(s.externalWaterML, 400)
        XCTAssertEqual(s.otherDeviceWaterML, 0)
    }

    /// 7. A snapshot from yesterday gives ext = 0.
    func testYesterdaySnapshotIsIgnored() {
        let yesterday = Fixtures.date(2025, 9, 24, 22, 0, 0)
        let snapshot = TodayMath.makeSnapshot(samples: [Fixtures.sample(date: yesterday, waterML: 900, entryID: nil)],
                                              localEntryIDs: [], now: yesterday, readAt: yesterday, calendar: cal)
        XCTAssertEqual(snapshot.dayStart, Fixtures.date(2025, 9, 24))
        XCTAssertEqual(snapshot.externalWaterML, 900)
        let e = Fixtures.entry(date: now.addingTimeInterval(-60), volumeML: 200)
        let s = TodayMath.summary(snapshot: snapshot, local: [e], goalML: 2000, now: now, calendar: cal)
        XCTAssertEqual(s.waterML, 200)
        XCTAssertEqual(s.externalWaterML, 0)
        XCTAssertNil(s.healthReadAt)
        let none = TodayMath.summary(snapshot: nil, local: [e], goalML: 2000, now: now, calendar: cal)
        XCTAssertEqual(none.waterML, 200)
        XCTAssertNil(none.healthReadAt)
    }

    /// 8. With an empty journal (reinstall), this device's old samples are counted once.
    func testEmptyJournalCountsOwnOldSamplesOnce() {
        let samples = [
            Fixtures.sample(date: now.addingTimeInterval(-7200), waterML: 250, entryID: UUID(), origin: .phone),
            Fixtures.sample(date: now.addingTimeInterval(-3600), waterML: 500, entryID: UUID(), origin: .phone)
        ]
        let s = total(samples: samples, journal: [])
        XCTAssertEqual(s.waterML, 750)
        XCTAssertEqual(s.localWaterML, 0)
    }

    /// 9. undoAvailableUntil boundary cases.
    func testUndoAvailableUntilBoundaries() {
        let inside = Fixtures.entry(date: now.addingTimeInterval(-599))
        XCTAssertEqual(total(samples: [], journal: [inside]).undoAvailableUntil, inside.date.addingTimeInterval(600))

        let edge = Fixtures.entry(date: now.addingTimeInterval(-600))   // until == now → not > now
        XCTAssertNil(total(samples: [], journal: [edge]).undoAvailableUntil)
        XCTAssertEqual(total(samples: [], journal: [edge]).lastLocal, edge)

        let outside = Fixtures.entry(date: now.addingTimeInterval(-601))
        XCTAssertNil(total(samples: [], journal: [outside]).undoAvailableUntil)

        // Only the newest VISIBLE entry counts: a hidden newer one does not extend the window.
        let hiddenNewer = Fixtures.entry(date: now.addingTimeInterval(-10), health: .pendingDelete)
        let s = total(samples: [], journal: [outside, hiddenNewer])
        XCTAssertEqual(s.lastLocal, outside)
        XCTAssertNil(s.undoAvailableUntil)

        // lastLocal is the newest by date, not by array order.
        let a = Fixtures.entry(date: now.addingTimeInterval(-120))
        let b = Fixtures.entry(date: now.addingTimeInterval(-30))
        XCTAssertEqual(total(samples: [], journal: [b, a]).lastLocal, b)
        XCTAssertEqual(total(samples: [], journal: [b, a]).undoAvailableUntil, b.date.addingTimeInterval(600))
    }

    /// 10. Midnight rollover.
    func testMidnightRollover() {
        let lateYesterday = Fixtures.entry(date: Fixtures.date(2025, 9, 24, 23, 59, 59), volumeML: 300, health: .saved)
        let atMidnight = Fixtures.entry(date: Fixtures.date(2025, 9, 25, 0, 0, 0), volumeML: 200)
        let journal = [lateYesterday, atMidnight]

        // Before midnight: yesterday's entry counts, and the undo window is live.
        let before = Fixtures.date(2025, 9, 24, 23, 59, 59)
        let snapBefore = TodayMath.makeSnapshot(
            samples: [Fixtures.sample(date: Fixtures.date(2025, 9, 24, 20, 0, 0), waterML: 1000, entryID: nil)],
            localEntryIDs: Set(journal.map(\.id)), now: before, readAt: before, calendar: cal)
        let s1 = TodayMath.summary(snapshot: snapBefore, local: [lateYesterday], goalML: 2000, now: before, calendar: cal)
        XCTAssertEqual(s1.waterML, 1300)
        XCTAssertEqual(s1.lastLocal, lateYesterday)

        // After midnight: yesterday's snapshot is ignored, the midnight entry belongs to the new day only.
        let after = Fixtures.date(2025, 9, 25, 0, 0, 30)
        let s2 = TodayMath.summary(snapshot: snapBefore, local: journal, goalML: 2000, now: after, calendar: cal)
        XCTAssertEqual(s2.waterML, 200)
        XCTAssertEqual(s2.externalWaterML, 0)
        XCTAssertEqual(s2.lastLocal, atMidnight)
        XCTAssertEqual(s2.undoAvailableUntil, atMidnight.date.addingTimeInterval(600))
        XCTAssertNil(s2.healthReadAt)

        // A sample stamped exactly at the next midnight is not part of the previous day.
        let snap = TodayMath.makeSnapshot(samples: [Fixtures.sample(date: Fixtures.date(2025, 9, 25), waterML: 700, entryID: nil)],
                                          localEntryIDs: [], now: before, readAt: before, calendar: cal)
        XCTAssertEqual(snap.externalWaterML, 0)

        // The first query after midnight counts it for the new day.
        let snapAfter = TodayMath.makeSnapshot(samples: [Fixtures.sample(date: Fixtures.date(2025, 9, 25), waterML: 700, entryID: nil)],
                                               localEntryIDs: [], now: after, readAt: after, calendar: cal)
        XCTAssertEqual(TodayMath.summary(snapshot: snapAfter, local: [], goalML: 2000, now: after, calendar: cal).waterML, 700)
    }

    // MARK: - Other summary fields

    func testSnapshotMathAndSummaryFields() {
        let readAt = now.addingTimeInterval(-5)
        let local = [
            Fixtures.entry(date: now.addingTimeInterval(-50), volumeML: 250, waterML: 250, health: .saved),
            Fixtures.entry(date: Fixtures.date(2025, 9, 20, 10), volumeML: 500, health: .pending),  // old pending
            Fixtures.entry(date: now.addingTimeInterval(-40), volumeML: 330, waterML: 297, health: .pending)
        ]
        let samples = [
            Fixtures.sample(date: local[0].date, waterML: 250, entryID: local[0].id),
            Fixtures.sample(date: now.addingTimeInterval(-900), waterML: 100.4, entryID: nil),
            Fixtures.sample(date: now.addingTimeInterval(-800), waterML: 200.3, entryID: UUID()),
            Fixtures.sample(date: Fixtures.date(2025, 9, 24, 23), waterML: 999, entryID: nil)   // yesterday
        ]
        let snapshot = TodayMath.makeSnapshot(samples: samples, localEntryIDs: Set(local.map(\.id)), now: now,
                                              readAt: readAt, calendar: cal)
        XCTAssertEqual(snapshot.dayStart, todayStart)
        XCTAssertEqual(snapshot.externalWaterML, 300.7, accuracy: 0.0001)
        XCTAssertEqual(snapshot.otherDeviceWaterML, 200.3, accuracy: 0.0001)
        XCTAssertEqual(snapshot.readAt, readAt)

        let s = TodayMath.summary(snapshot: snapshot, local: local, goalML: 2500, now: now, calendar: cal)
        XCTAssertEqual(s.waterML, 848)          // 300.7 + 547 = 847.7
        XCTAssertEqual(s.localWaterML, 547)
        XCTAssertEqual(s.externalWaterML, 301)
        XCTAssertEqual(s.otherDeviceWaterML, 200)
        XCTAssertEqual(s.goalML, 2500)
        XCTAssertEqual(s.pendingCount, 2)       // any day
        XCTAssertEqual(s.lastLocal, local[2])
        XCTAssertEqual(s.healthReadAt, readAt)
        XCTAssertEqual(s.progress, 848.0 / 2500.0, accuracy: 1e-9)
    }

    func testSnapshotSurvivesJSONRoundTrip() throws {
        let snapshot = TodayMath.makeSnapshot(samples: [Fixtures.sample(date: now, waterML: 250, entryID: nil)],
                                              localEntryIDs: [], now: now, readAt: now, calendar: cal)
        let decoded = try CoreJSON.decoder().decode(HealthSnapshot.self, from: CoreJSON.encoder().encode(snapshot))
        XCTAssertEqual(TodayMath.summary(snapshot: decoded, local: [], goalML: 2000, now: now, calendar: cal).waterML, 250)
    }

    func testProgressAndPlaceholder() {
        XCTAssertEqual(TodaySummary.placeholder.waterML, 1200)
        XCTAssertEqual(TodaySummary.placeholder.goalML, 2000)
        XCTAssertEqual(TodaySummary.placeholder.localWaterML, 0)
        XCTAssertEqual(TodaySummary.placeholder.externalWaterML, 0)
        XCTAssertEqual(TodaySummary.placeholder.otherDeviceWaterML, 0)
        XCTAssertEqual(TodaySummary.placeholder.pendingCount, 0)
        XCTAssertNil(TodaySummary.placeholder.lastLocal)
        XCTAssertNil(TodaySummary.placeholder.undoAvailableUntil)
        XCTAssertNil(TodaySummary.placeholder.healthReadAt)
        XCTAssertEqual(TodaySummary.placeholder.progress, 0.6, accuracy: 1e-9)
        var s = TodaySummary.placeholder
        s.waterML = 5000
        XCTAssertEqual(s.progress, 1)
        s.waterML = -10
        XCTAssertEqual(s.progress, 0)
        s.waterML = 100
        s.goalML = 0
        XCTAssertEqual(s.progress, 1)
    }

    // MARK: - Local daily totals

    func testLocalDailyTotalsOldestFirstVisibleOnly() {
        let entries = [
            Fixtures.entry(date: Fixtures.date(2025, 9, 23, 9), volumeML: 250, health: .saved),
            Fixtures.entry(date: Fixtures.date(2025, 9, 23, 23, 59, 59), volumeML: 500, health: .pending),
            Fixtures.entry(date: Fixtures.date(2025, 9, 24, 0, 0, 0), volumeML: 330, health: .saved),
            Fixtures.entry(date: Fixtures.date(2025, 9, 24, 12), volumeML: 1000, health: .deleted),
            Fixtures.entry(date: Fixtures.date(2025, 9, 25, 8), volumeML: 200, health: .pendingDelete),
            Fixtures.entry(date: Fixtures.date(2025, 9, 25, 9), volumeML: 150, health: .pending),
            Fixtures.entry(date: Fixtures.date(2025, 9, 10, 9), volumeML: 999, health: .saved)   // outside range
        ]
        let totals = TodayMath.localDailyTotals(entries, days: 3, now: now, calendar: cal)
        XCTAssertEqual(totals, [
            DayTotal(dayStart: Fixtures.date(2025, 9, 23), waterML: 750),
            DayTotal(dayStart: Fixtures.date(2025, 9, 24), waterML: 330),
            DayTotal(dayStart: Fixtures.date(2025, 9, 25), waterML: 150)
        ])
        XCTAssertEqual(totals.map(\.id), totals.map(\.dayStart))
        XCTAssertEqual(TodayMath.localDailyTotals(entries, days: 7, now: now, calendar: cal).count, 7)
        XCTAssertEqual(TodayMath.localDailyTotals(entries, days: 0, now: now, calendar: cal), [])
    }
}
