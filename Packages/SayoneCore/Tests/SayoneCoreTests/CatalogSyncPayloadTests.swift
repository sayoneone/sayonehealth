import Foundation
import XCTest
@testable import SayoneCore

final class CatalogSyncPayloadTests: XCTestCase {
    private let updatedAt = Date(timeIntervalSince1970: 1_758_800_000)

    private func catalog(revision: Int64) -> Catalog {
        var c = Catalog.makeDefault(revision: revision, now: updatedAt)
        c.settings.dailyGoalML = 2500
        c.presets.reverse()
        return c
    }

    func testKeys() {
        XCTAssertEqual(CatalogSyncPayload.catalogKey, "catalog")
        XCTAssertEqual(CatalogSyncPayload.revisionKey, "revision")
    }

    func testEncode() throws {
        let c = catalog(revision: 1_758_800_000_123)
        let payload = try CatalogSyncPayload.encode(c)
        XCTAssertEqual(Set(payload.keys), ["catalog", "revision"])
        let data = try XCTUnwrap(payload["catalog"] as? Data)
        XCTAssertEqual(try CoreJSON.decoder().decode(Catalog.self, from: data), c)
        let revision = try XCTUnwrap(payload["revision"] as? NSNumber)
        XCTAssertEqual(revision.int64Value, 1_758_800_000_123)
    }

    func testDecodeRoundTrip() throws {
        let c = catalog(revision: 1_758_800_000_123)
        XCTAssertEqual(CatalogSyncPayload.decode(try CatalogSyncPayload.encode(c)), c)
    }

    func testDecodeSanitizes() throws {
        var c = catalog(revision: 5)
        c.settings.dailyGoalML = 1
        c.presets.append(Preset(id: "orphan", drinkID: "custom-gone", volumeML: 250))
        let decoded = try XCTUnwrap(CatalogSyncPayload.decode(try CatalogSyncPayload.encode(c)))
        XCTAssertEqual(decoded, c.sanitized())
        XCTAssertEqual(decoded.settings.dailyGoalML, 500)
    }

    func testDecodeFailures() {
        XCTAssertNil(CatalogSyncPayload.decode([:]))
        XCTAssertNil(CatalogSyncPayload.decode(["revision": NSNumber(value: Int64(5))]))
        XCTAssertNil(CatalogSyncPayload.decode(["catalog": "not data"]))
        XCTAssertNil(CatalogSyncPayload.decode(["catalog": Data("garbage".utf8)]))
        XCTAssertNil(CatalogSyncPayload.decode(["catalog": Data("{}".utf8)]))
    }

    func testDecodeIgnoresRevisionKey() throws {
        let c = catalog(revision: 77)
        var payload = try CatalogSyncPayload.encode(c)
        payload["revision"] = NSNumber(value: Int64(1))
        XCTAssertEqual(CatalogSyncPayload.decode(payload)?.revision, 77)
    }

    func testShouldApplyNewestRevisionWins() {
        XCTAssertTrue(CatalogSyncPayload.shouldApply(received: catalog(revision: 11), current: catalog(revision: 10)))
        XCTAssertFalse(CatalogSyncPayload.shouldApply(received: catalog(revision: 10), current: catalog(revision: 10)))
        XCTAssertFalse(CatalogSyncPayload.shouldApply(received: catalog(revision: 9), current: catalog(revision: 10)))
        XCTAssertTrue(CatalogSyncPayload.shouldApply(received: catalog(revision: 1_758_800_000_123),
                                                     current: catalog(revision: 1_758_800_000_122)))
    }
}
