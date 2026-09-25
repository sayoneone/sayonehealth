import Foundation
import XCTest
@testable import SayoneCore

final class CatalogStoreTests: TemporaryDirectoryTestCase {
    private let now = Date(timeIntervalSince1970: 1_758_800_000.123_4)
    private var fileURL: URL { tempDirectory.appendingPathComponent("catalog.json") }
    private var backupURL: URL { tempDirectory.appendingPathComponent("catalog.json.bak") }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testMissingFileGivesDefaultRevisionZeroForBothRolesAndWritesNothing() {
        for role in [CatalogRole.author, .replica] {
            let c = CatalogStore(fileURL: fileURL, role: role).load(now: now)
            XCTAssertEqual(c, Catalog.makeDefault(revision: 0, now: now))
            XCTAssertFalse(exists(fileURL))
            XCTAssertFalse(exists(backupURL))
        }
    }

    func testMissingDirectoryIsFine() throws {
        let nested = tempDirectory.appendingPathComponent("a/b/catalog.json")
        let store = CatalogStore(fileURL: nested, role: .author)
        XCTAssertEqual(store.load(now: now).revision, 0)
        try store.save(Catalog.makeDefault(revision: 9, now: now))
        XCTAssertEqual(store.load(now: now).revision, 9)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = CatalogStore(fileURL: fileURL, role: .author)
        var c = Catalog.makeDefault(revision: 1_758_800_000_123, now: Date(timeIntervalSince1970: 1_758_800_000))
        _ = CatalogEditor.addCustomDrink(to: &c, name: "Kvass", symbol: "leaf.fill", tint: .brown, hydrationFactor: 0.9,
                                         per100ML: NutrientsPer100ML(energyKcal: 27), defaultVolumeML: 330,
                                         now: Date(timeIntervalSince1970: 1_758_800_001))
        try store.save(c)
        XCTAssertEqual(store.load(now: now), c)
        XCTAssertEqual(CatalogStore(fileURL: fileURL, role: .replica).load(now: now), c)
    }

    func testSaveWritesSanitizedCatalog() throws {
        let store = CatalogStore(fileURL: fileURL, role: .author)
        var c = Catalog.makeDefault(revision: 3, now: Date(timeIntervalSince1970: 1_758_800_000))
        c.settings.dailyGoalML = 1
        c.drinks.removeAll { $0.id == "milk" }
        try store.save(c)
        let raw = try CoreJSON.decoder().decode(Catalog.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(raw.settings.dailyGoalML, 500)
        XCTAssertNotNil(raw.drink(id: "milk"))
    }

    func testCorruptFileForAuthorUsesEpochRevisionAndKeepsBackup() throws {
        let garbage = Data("{not json".utf8)
        try garbage.write(to: fileURL)
        try Data("old backup".utf8).write(to: backupURL)
        let c = CatalogStore(fileURL: fileURL, role: .author).load(now: now)
        XCTAssertEqual(c.revision, 1_758_800_000_123)
        XCTAssertEqual(c.revision, Int64(now.timeIntervalSince1970 * 1000))
        XCTAssertEqual(c.drinks, BuiltInCatalog.allDrinks)
        XCTAssertEqual(c.presets, BuiltInCatalog.defaultPresets)
        XCTAssertFalse(exists(fileURL), "load never writes a catalog")
        XCTAssertEqual(try Data(contentsOf: backupURL), garbage, "the corrupt file replaces any old backup")
    }

    /// After a recovery the phone keeps returning a revision newer than anything the watch holds, on every
    /// later load (not only the first), so the default catalog it pushes is accepted.
    func testAuthorRecoveryRevisionIsStableOnLaterLoads() throws {
        try Data("{broken".utf8).write(to: fileURL)
        let store = CatalogStore(fileURL: fileURL, role: .author)
        let first = store.load(now: now)
        let later = store.load(now: now.addingTimeInterval(3600))
        let evenLater = store.load(now: now.addingTimeInterval(7200))
        XCTAssertEqual(later.revision, evenLater.revision)
        XCTAssertLessThanOrEqual(abs(later.revision - first.revision), 1000)
        let watchCatalog = Catalog.makeDefault(revision: first.revision - 60_000, now: now)
        XCTAssertTrue(CatalogSyncPayload.shouldApply(received: later, current: watchCatalog))
        XCTAssertEqual(CatalogStore(fileURL: fileURL, role: .replica).load(now: now).revision, 0,
                       "replicas never use the backup date")
    }

    func testCorruptFileForReplicaUsesRevisionZero() throws {
        try Data("[]".utf8).write(to: fileURL)
        let c = CatalogStore(fileURL: fileURL, role: .replica).load(now: now)
        XCTAssertEqual(c.revision, 0)
        XCTAssertEqual(c, Catalog.makeDefault(revision: 0, now: now))
        XCTAssertFalse(exists(fileURL))
        XCTAssertTrue(exists(backupURL))
    }

    func testAuthorFallbackWinsOnReplicaAndReplicaFallbackAcceptsAnything() throws {
        try Data("corrupt".utf8).write(to: fileURL)
        let author = CatalogStore(fileURL: fileURL, role: .author).load(now: now)
        let watchCatalog = Catalog.makeDefault(revision: 1_758_000_000_000, now: now)
        XCTAssertTrue(CatalogSyncPayload.shouldApply(received: author, current: watchCatalog))

        let replicaFile = tempDirectory.appendingPathComponent("replica.json")
        try Data("corrupt".utf8).write(to: replicaFile)
        let replica = CatalogStore(fileURL: replicaFile, role: .replica).load(now: now)
        XCTAssertTrue(CatalogSyncPayload.shouldApply(received: Catalog.makeDefault(revision: 1, now: now), current: replica))
    }

    func testLoadAlwaysSanitizes() throws {
        var c = Catalog.makeDefault(revision: 11, now: Date(timeIntervalSince1970: 1_758_800_000))
        c.settings.dailyGoalML = 99_999
        c.presets.append(Preset(id: "orphan", drinkID: "custom-missing", volumeML: 250))
        c.version = 0
        try CoreJSON.encoder().encode(c).write(to: fileURL)   // bypass save()'s sanitize
        let loaded = CatalogStore(fileURL: fileURL, role: .replica).load(now: now)
        XCTAssertEqual(loaded.settings.dailyGoalML, 6000)
        XCTAssertFalse(loaded.presets.contains { $0.id == "orphan" })
        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.revision, 11)
    }
}
