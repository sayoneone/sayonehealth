import Foundation

/// Cached result of the last HealthKit water read for today (see `TodayMath.makeSnapshot`).
public struct HealthSnapshot: Codable, Hashable, Sendable {
    public var dayStart: Date
    /// Today's HealthKit water NOT written by entries in this device's journal.
    public var externalWaterML: Double
    /// The part of `externalWaterML` that carries a SayoneEntryID (our app on the other device).
    public var otherDeviceWaterML: Double
    /// Captured BEFORE the HealthKit query was issued.
    public var readAt: Date

    public init(dayStart: Date, externalWaterML: Double, otherDeviceWaterML: Double, readAt: Date) {
        self.dayStart = dayStart
        self.externalWaterML = externalWaterML
        self.otherDeviceWaterML = otherDeviceWaterML
        self.readAt = readAt
    }
}
