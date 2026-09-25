import Foundation
import XCTest
@testable import SayoneCore

final class JournalStoreTests: TemporaryDirectoryTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_758_800_000)
    private let at = Date(timeIntervalSince1970: 1_758_800_100)
    private var journalDir: URL { tempDirectory.appendingPathComponent("Journal", isDirectory: true) }
    private var store: JournalStore { JournalStore(directory: journalDir) }

    private func jsonFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: journalDir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted()
    }

    /// Writes an entry already in `status` (create() stores the entry exactly as given).
    @discardableResult
    private func seed(_ status: HealthSyncStatus, date: Date? = nil, source: LogSource = .app) throws -> IntakeEntry {
        let entry = Fixtures.entry(date: date ?? t0, health: status, source: source)
        guard case .created = try store.create(entry) else {
            XCTFail("seed failed")
            return entry
        }
        return entry
    }

    // MARK: - Basics

    func testInitDoesNoIOAndFirstWriteCreatesDirectory() throws {
        _ = store
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalDir.path))
        XCTAssertEqual(store.all(), [])
        XCTAssertNil(store.entry(id: UUID()))
        XCTAssertEqual(try store.prune(now: t0), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalDir.path))
        let e = try seed(.pending)
        XCTAssertEqual(jsonFiles(), ["\(e.id.uuidString).json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalDir.appendingPathComponent(".lock").path))
        XCTAssertEqual(JournalStore.retentionDays, 8)
        XCTAssertEqual(store.directory, journalDir)
    }

    // MARK: - State machine: create

    func testCreateWhenMissingWritesFile() throws {
        let e = Fixtures.entry(date: t0)
        XCTAssertEqual(try store.create(e), .created(e))
        XCTAssertEqual(store.entry(id: e.id), e)
    }

    func testCreateWithExistingIDReturnsExistingInEveryStatus() throws {
        for status in HealthSyncStatus.allCases {
            let stored = try seed(status)
            let again = Fixtures.entry(id: stored.id, date: t0.addingTimeInterval(50), volumeML: 999)
            XCTAssertEqual(try store.create(again), .existing(stored), "\(status)")
            XCTAssertEqual(store.entry(id: stored.id), stored, "\(status) file untouched")
        }
    }

    // MARK: - State machine: markSaved

    func testMarkSavedMissing() throws {
        XCTAssertEqual(try store.markSaved(id: UUID(), at: at), .missing)
    }

    func testMarkSavedPending() throws {
        let e = try seed(.pending)
        XCTAssertEqual(try store.markSaved(id: e.id, at: at), .marked)
        let stored = store.entry(id: e.id)
        XCTAssertEqual(stored?.health, .saved)
        XCTAssertEqual(stored?.healthSavedAt, at)
        XCTAssertNil(stored?.deletedAt)
    }

    func testMarkSavedSaved() throws {
        let e = try seed(.saved)
        XCTAssertEqual(try store.markSaved(id: e.id, at: at), .alreadySaved)
        XCTAssertEqual(store.entry(id: e.id), e)
    }

    func testMarkSavedPendingDeleteIsUnchanged() throws {
        let e = try seed(.pendingDelete)
        XCTAssertEqual(try store.markSaved(id: e.id, at: at), .deletedMeanwhile)
        XCTAssertEqual(store.entry(id: e.id), e)
    }

    func testMarkSavedDeletedIsUnchanged() throws {
        let e = try seed(.deleted)
        XCTAssertEqual(try store.markSaved(id: e.id, at: at), .deletedMeanwhile)
        XCTAssertEqual(store.entry(id: e.id), e)
    }

    // MARK: - State machine: beginDelete

    func testBeginDeleteMissing() throws {
        XCTAssertEqual(try store.beginDelete(id: UUID(), at: at), .notFound)
        XCTAssertEqual(jsonFiles(), [])
    }

    func testBeginDeletePending() throws {
        let e = try seed(.pending)
        var expected = e
        expected.health = .pendingDelete
        expected.deletedAt = at
        XCTAssertEqual(try store.beginDelete(id: e.id, at: at), .began(previous: .pending, entry: expected))
        XCTAssertEqual(store.entry(id: e.id), expected)
    }

    func testBeginDeleteSaved() throws {
        let e = try seed(.saved)
        var expected = e
        expected.health = .pendingDelete
        expected.deletedAt = at
        XCTAssertEqual(try store.beginDelete(id: e.id, at: at), .began(previous: .saved, entry: expected))
        XCTAssertEqual(store.entry(id: e.id)?.health, .pendingDelete)
        XCTAssertEqual(store.entry(id: e.id)?.healthSavedAt, e.healthSavedAt)
    }

    func testBeginDeletePendingDelete() throws {
        let e = try seed(.pendingDelete)
        XCTAssertEqual(try store.beginDelete(id: e.id, at: at), .alreadyDeleting(e))
        XCTAssertEqual(store.entry(id: e.id), e)
    }

    func testBeginDeleteDeleted() throws {
        let e = try seed(.deleted)
        XCTAssertEqual(try store.beginDelete(id: e.id, at: at), .alreadyDeleted)
        XCTAssertEqual(store.entry(id: e.id), e)
    }

    // MARK: - State machine: finishDelete

    func testFinishDeleteMissingIsNoOp() throws {
        try store.finishDelete(id: UUID(), at: at)
        XCTAssertEqual(jsonFiles(), [])
    }

    func testFinishDeleteFromEveryLiveStatus() throws {
        for status in [HealthSyncStatus.pending, .saved, .pendingDelete] {
            let e = try seed(status)
            try store.finishDelete(id: e.id, at: at)
            let stored = store.entry(id: e.id)
            XCTAssertEqual(stored?.health, .deleted, "\(status)")
            XCTAssertEqual(stored?.deletedAt, at, "\(status)")
        }
    }

    func testFinishDeleteDeletedIsNoOp() throws {
        let e = try seed(.deleted)
        try store.finishDelete(id: e.id, at: at)
        XCTAssertEqual(store.entry(id: e.id), e)
    }

    func testNothingLeavesPendingDeleteExceptToDeleted() throws {
        let e = try seed(.pending)
        _ = try store.beginDelete(id: e.id, at: at)
        XCTAssertEqual(try store.markSaved(id: e.id, at: at), .deletedMeanwhile)
        XCTAssertEqual(try store.create(e), .existing(store.entry(id: e.id)!))
        XCTAssertEqual(store.entry(id: e.id)?.health, .pendingDelete)
        try store.finishDelete(id: e.id, at: at)
        XCTAssertEqual(try store.markSaved(id: e.id, at: at), .deletedMeanwhile)
        XCTAssertEqual(try store.beginDelete(id: e.id, at: at), .alreadyDeleted)
        XCTAssertEqual(store.entry(id: e.id)?.health, .deleted)
    }

    // MARK: - Concurrency

    func testHundredConcurrentCreatesGiveHundredFiles() throws {
        let entries = (0..<100).map { i in
            Fixtures.entry(date: t0.addingTimeInterval(Double(i) * 0.01), volumeML: 100 + i, source: .app)
        }
        let local = store
        var results = [CreateResult?](repeating: nil, count: entries.count)
        let resultsLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let r = try? local.create(entries[i])
            resultsLock.lock()
            results[i] = r
            resultsLock.unlock()
        }
        XCTAssertEqual(jsonFiles().count, 100)
        XCTAssertEqual(store.all().count, 100)
        for (i, r) in results.enumerated() {
            XCTAssertEqual(r, .created(entries[i]))
        }
    }

    func testConcurrentWidgetDoubleTapsCollapse() throws {
        // 20 processes/threads racing the same widget tap within the dedupe window → exactly one file.
        let entries = (0..<20).map { i in
            Fixtures.entry(date: t0.addingTimeInterval(Double(i) * 0.05), volumeML: 500, source: .widget)
        }
        let local = store
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            _ = try? local.create(entries[i])
        }
        XCTAssertEqual(jsonFiles().count, 1)
    }

    func testConcurrentMarkSavedAndBeginDeleteNeverResurrect() throws {
        let entries = try (0..<40).map { _ in try seed(.pending) }
        let local = store
        DispatchQueue.concurrentPerform(iterations: entries.count * 2) { i in
            let id = entries[i / 2].id
            if i % 2 == 0 {
                _ = try? local.markSaved(id: id, at: Date())
            } else {
                _ = try? local.beginDelete(id: id, at: Date())
            }
        }
        for e in entries {
            XCTAssertEqual(store.entry(id: e.id)?.health, .pendingDelete)
        }
    }

    // MARK: - Dedupe

    func testWidgetCreatesOneSecondApartGiveOneFile() throws {
        let first = Fixtures.entry(date: t0, drinkID: "water", volumeML: 500, source: .widget)
        let second = Fixtures.entry(date: t0.addingTimeInterval(1), drinkID: "water", volumeML: 500, source: .widget)
        XCTAssertEqual(try store.create(first), .created(first))
        XCTAssertEqual(try store.create(second), .duplicate(first))
        XCTAssertEqual(jsonFiles(), ["\(first.id.uuidString).json"])
    }

    func testAppCreatesAreNeverCollapsed() throws {
        let first = Fixtures.entry(date: t0, volumeML: 500, source: .app)
        let second = Fixtures.entry(date: t0.addingTimeInterval(1), volumeML: 500, source: .app)
        XCTAssertEqual(try store.create(first), .created(first))
        XCTAssertEqual(try store.create(second), .created(second))
        XCTAssertEqual(jsonFiles().count, 2)
    }

    func testWidgetCreatesThreeSecondsApartAreKept() throws {
        let first = Fixtures.entry(date: t0, volumeML: 500, source: .widget)
        let second = Fixtures.entry(date: t0.addingTimeInterval(3), volumeML: 500, source: .widget)
        XCTAssertEqual(try store.create(first), .created(first))
        XCTAssertEqual(try store.create(second), .created(second))
    }

    // MARK: - Prune

    func testPruneRemovesOnlyOldSavedAndDeleted() throws {
        let cal = Fixtures.moscow
        let now = Fixtures.date(2025, 9, 25, 12)
        let old = Fixtures.date(2025, 9, 17, 11, 59)   // older than now − 8 days
        let recent = Fixtures.date(2025, 9, 17, 12, 1)
        let oldPending = try seed(.pending, date: old)
        let oldDeleting = try seed(.pendingDelete, date: old)
        let oldSaved = try seed(.saved, date: old)
        let oldDeleted = try seed(.deleted, date: old)
        let recentSaved = try seed(.saved, date: recent)
        let recentDeleted = try seed(.deleted, date: recent)

        XCTAssertEqual(try store.prune(now: now, calendar: cal), 2)
        let ids = Set(store.all().map(\.id))
        XCTAssertTrue(ids.contains(oldPending.id))
        XCTAssertTrue(ids.contains(oldDeleting.id))
        XCTAssertFalse(ids.contains(oldSaved.id))
        XCTAssertFalse(ids.contains(oldDeleted.id))
        XCTAssertTrue(ids.contains(recentSaved.id))
        XCTAssertTrue(ids.contains(recentDeleted.id))
        XCTAssertEqual(try store.prune(now: now, calendar: cal), 0)
    }

    // MARK: - Reads

    func testAllSkipsJunkAndSortsByDate() throws {
        let late = try seed(.saved, date: t0.addingTimeInterval(100))
        let early = try seed(.pending, date: t0)
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: journalDir.appendingPathComponent(".hidden.json"))
        try Data("junk".utf8).write(to: journalDir.appendingPathComponent("\(UUID().uuidString).json"))
        try CoreJSON.encoder().encode(Fixtures.entry(date: t0)).write(to: journalDir.appendingPathComponent("note.txt"))
        XCTAssertEqual(store.all(), [early, late])
    }

    func testEntriesInIntervalAndNeedingFlush() throws {
        let a = try seed(.saved, date: t0)
        let b = try seed(.pendingDelete, date: t0.addingTimeInterval(10))
        let c = try seed(.pending, date: t0.addingTimeInterval(5))
        let d = try seed(.deleted, date: t0.addingTimeInterval(20))
        let e = try seed(.pending, date: t0.addingTimeInterval(60))
        XCTAssertEqual(store.needingFlush(), [c, b, e])
        XCTAssertEqual(store.entries(in: DateInterval(start: t0, end: t0.addingTimeInterval(60))), [a, c, b, d])
        _ = e
    }

    // MARK: - Lock

    func testFileLockThrowsWhenLockFileCannotBeOpened() {
        let url = tempDirectory.appendingPathComponent("no/such/dir/.lock")
        XCTAssertThrowsError(try FileLock.withExclusiveLock(at: url) { 1 }) { error in
            guard case FileLockError.open = error else { return XCTFail("\(error)") }
        }
    }

    func testBestEffortRunsBodyOnceWithoutLockAndPropagatesBodyErrors() throws {
        var runs = 0
        let bad = tempDirectory.appendingPathComponent("no/such/dir/.lock")
        XCTAssertEqual(try FileLock.bestEffort(at: bad) { () -> Int in runs += 1; return 7 }, 7)
        XCTAssertEqual(runs, 1)

        runs = 0
        let good = tempDirectory.appendingPathComponent(".lock")
        XCTAssertThrowsError(try FileLock.bestEffort(at: good) { () -> Int in
            runs += 1
            throw FileLockError.lock(99)
        })
        XCTAssertEqual(runs, 1, "a FileLockError thrown by the body must not re-run it")
    }

    func testFileLockSerializesCriticalSections() throws {
        let url = tempDirectory.appendingPathComponent(".lock")
        let counterURL = tempDirectory.appendingPathComponent("counter")
        try Data("0".utf8).write(to: counterURL)
        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            _ = try? FileLock.withExclusiveLock(at: url) {
                let value = Int(String(decoding: (try? Data(contentsOf: counterURL)) ?? Data(), as: UTF8.self)) ?? -1000
                try? Data("\(value + 1)".utf8).write(to: counterURL, options: .atomic)
            }
        }
        XCTAssertEqual(String(decoding: try Data(contentsOf: counterURL), as: UTF8.self), "50")
    }
}
