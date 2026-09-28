import Foundation
import XCTest
@testable import SayoneCore

final class SnapshotStoreTests: TemporaryDirectoryTestCase {
    private var fileURL: URL { tempDirectory.appendingPathComponent("SayoneHealth/health-snapshot.json") }

    private func snapshot(readAt seconds: TimeInterval, external: Double) -> HealthSnapshot {
        HealthSnapshot(dayStart: Date(timeIntervalSince1970: 1_758_747_600), externalWaterML: external,
                       otherDeviceWaterML: 0, readAt: Date(timeIntervalSince1970: 1_758_800_000 + seconds))
    }

    func testLoadMissingIsNil() {
        XCTAssertNil(SnapshotStore(fileURL: fileURL).load())
    }

    func testSaveCreatesDirectoryAndLock() throws {
        let store = SnapshotStore(fileURL: fileURL)
        XCTAssertEqual(store.fileURL, fileURL)
        let s = snapshot(readAt: 0, external: 100)
        try store.saveIfNewer(s)
        XCTAssertEqual(store.load(), s)
        let lock = fileURL.deletingLastPathComponent().appendingPathComponent(".snapshot.lock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lock.path))
    }

    func testNewerReplacesOlderIsSkipped() throws {
        let store = SnapshotStore(fileURL: fileURL)
        try store.saveIfNewer(snapshot(readAt: 10, external: 100))
        try store.saveIfNewer(snapshot(readAt: 20, external: 200))
        XCTAssertEqual(store.load()?.externalWaterML, 200)
        try store.saveIfNewer(snapshot(readAt: 15, external: 150))   // slow reader finishing late
        XCTAssertEqual(store.load()?.externalWaterML, 200)
        try store.saveIfNewer(snapshot(readAt: 20, external: 250))   // same readAt: not older, so it is written
        XCTAssertEqual(store.load()?.externalWaterML, 250)
    }

    func testCorruptFileIsReplaced() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: fileURL)
        let store = SnapshotStore(fileURL: fileURL)
        XCTAssertNil(store.load())
        try store.saveIfNewer(snapshot(readAt: 0, external: 42))
        XCTAssertEqual(store.load()?.externalWaterML, 42)
    }

    func testConcurrentWritersKeepTheNewest() throws {
        let store = SnapshotStore(fileURL: fileURL)
        DispatchQueue.concurrentPerform(iterations: 40) { i in
            try? store.saveIfNewer(snapshot(readAt: Double(i), external: Double(i)))
        }
        XCTAssertEqual(store.load()?.externalWaterML, 39)
    }
}
