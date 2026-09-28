import Foundation
import XCTest
@testable import SayoneCore

final class VolumeFormatTests: XCTestCase {
    private let n = Fixtures.nbsp

    func testSpecExamples() {
        XCTAssertEqual(VolumeFormat.short(250, .ru), "250\(n)мл")
        XCTAssertEqual(VolumeFormat.short(1500, .ru), "1,5\(n)л")
        XCTAssertEqual(VolumeFormat.short(1000, .en), "1\(n)L")
        XCTAssertEqual(VolumeFormat.progress(1200, goalML: 2000, .ru), "1,2 из 2\(n)л")
        XCTAssertEqual(VolumeFormat.progress(1250, goalML: 2000, .en), "1.3 of 2\(n)L")
        XCTAssertEqual(VolumeFormat.compact(500, .ru), "500")
    }

    func testNoBreakSpaceBetweenNumberAndUnit() {
        XCTAssertEqual(Array("250\u{00A0}мл".unicodeScalars).map(\.value)[3], 0xA0)
        XCTAssertFalse(VolumeFormat.short(250, .en).contains(" "))
        XCTAssertFalse(VolumeFormat.short(1500, .en).contains(" "))
        XCTAssertTrue(VolumeFormat.short(250, .en).contains("\u{00A0}"))
    }

    func testShort() {
        XCTAssertEqual(VolumeFormat.short(250, .en), "250\(n)ml")
        XCTAssertEqual(VolumeFormat.short(0, .ru), "0\(n)мл")
        XCTAssertEqual(VolumeFormat.short(999, .ru), "999\(n)мл")
        XCTAssertEqual(VolumeFormat.short(1000, .ru), "1\(n)л")
        XCTAssertEqual(VolumeFormat.short(1049, .ru), "1\(n)л")
        XCTAssertEqual(VolumeFormat.short(1050, .ru), "1,1\(n)л")
        XCTAssertEqual(VolumeFormat.short(1500, .en), "1.5\(n)L")
        XCTAssertEqual(VolumeFormat.short(2000, .en), "2\(n)L")
        XCTAssertEqual(VolumeFormat.short(5000, .ru), "5\(n)л")
        XCTAssertEqual(VolumeFormat.short(12_345, .en), "12.3\(n)L")
    }

    func testPlus() {
        XCTAssertEqual(VolumeFormat.plus(250, .ru), "+250\(n)мл")
        XCTAssertEqual(VolumeFormat.plus(1500, .en), "+1.5\(n)L")
    }

    func testCompact() {
        XCTAssertEqual(VolumeFormat.compact(500, .en), "500")
        XCTAssertEqual(VolumeFormat.compact(999, .ru), "999")
        XCTAssertEqual(VolumeFormat.compact(1000, .ru), "1\(n)л")
        XCTAssertEqual(VolumeFormat.compact(1500, .ru), "1,5\(n)л")
        XCTAssertEqual(VolumeFormat.compact(1500, .en), "1.5\(n)L")
    }

    func testLiters() {
        XCTAssertEqual(VolumeFormat.liters(250, .ru), "0,3\(n)л")    // 2.5 → 3 (away from zero)
        XCTAssertEqual(VolumeFormat.liters(249, .ru), "0,2\(n)л")
        XCTAssertEqual(VolumeFormat.liters(2000, .ru), "2\(n)л")
        XCTAssertEqual(VolumeFormat.liters(2000, .en), "2\(n)L")
        XCTAssertEqual(VolumeFormat.liters(0, .en), "0\(n)L")
        XCTAssertEqual(VolumeFormat.liters(40, .en), "0\(n)L")
        XCTAssertEqual(VolumeFormat.liters(50, .en), "0.1\(n)L")
        XCTAssertEqual(VolumeFormat.liters(1950, .ru), "2\(n)л")
        XCTAssertEqual(VolumeFormat.liters(-1500, .en), "-1.5\(n)L")
    }

    func testProgress() {
        XCTAssertEqual(VolumeFormat.progress(0, goalML: 2000, .ru), "0 из 2\(n)л")
        XCTAssertEqual(VolumeFormat.progress(1200, goalML: 2000, .en), "1.2 of 2\(n)L")
        XCTAssertEqual(VolumeFormat.progress(2750, goalML: 2500, .ru), "2,8 из 2,5\(n)л")
    }

    func testProgressCompact() {
        XCTAssertEqual(VolumeFormat.progressCompact(1200, goalML: 2000, .ru), "1,2 / 2\(n)л")
        XCTAssertEqual(VolumeFormat.progressCompact(1200, goalML: 2000, .en), "1.2 / 2\(n)L")
        XCTAssertEqual(VolumeFormat.progressCompact(300, goalML: 1500, .en), "0.3 / 1.5\(n)L")
    }
}
