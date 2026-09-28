import Foundation
import XCTest
@testable import SayoneCore

/// Shared fixtures. Every date helper works in Europe/Moscow (UTC+3, no DST).
enum Fixtures {
    static let nbsp = "\u{00A0}"

    static var moscow: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? TimeZone(secondsFromGMT: 3 * 3600)!
        return calendar
    }

    /// A wall-clock time in Moscow.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return moscow.date(from: components)!
    }

    static func entry(id: UUID = UUID(),
                      date: Date,
                      drinkID: String = "water",
                      drinkName: String = "Water",
                      volumeML: Int = 250,
                      waterML: Double? = nil,
                      health: HealthSyncStatus = .pending,
                      source: LogSource = .app,
                      origin: DeviceKind = .phone) -> IntakeEntry {
        IntakeEntry(id: id,
                    date: date,
                    drinkID: drinkID,
                    drinkName: drinkName,
                    symbol: "drop.fill",
                    volumeML: volumeML,
                    nutrients: Nutrients(waterML: waterML ?? Double(volumeML)),
                    origin: origin,
                    source: source,
                    health: health,
                    healthSavedAt: health == .saved ? date : nil,
                    deletedAt: (health == .pendingDelete || health == .deleted) ? date : nil)
    }

    static func sample(date: Date,
                       waterML: Double,
                       entryID: UUID?,
                       drinkName: String? = nil,
                       volumeML: Int? = nil,
                       origin: DeviceKind? = nil) -> HealthWaterSample {
        HealthWaterSample(date: date,
                          waterML: waterML,
                          entryID: entryID,
                          drinkID: entryID == nil ? nil : "water",
                          drinkName: drinkName,
                          volumeML: volumeML,
                          origin: origin)
    }
}

/// Gives each test its own temporary directory and removes it afterwards.
class TemporaryDirectoryTestCase: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SayoneCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory = tempDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }
}
