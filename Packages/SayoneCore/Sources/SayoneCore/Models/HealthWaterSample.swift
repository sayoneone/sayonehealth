import Foundation

/// A HealthKit dietaryWater sample as plain data, so the math around it is testable without HealthKit.
public struct HealthWaterSample: Hashable, Sendable {
    /// Sample startDate.
    public let date: Date
    public let waterML: Double
    /// SayoneEntryID; nil for samples from other apps.
    public let entryID: UUID?
    /// SayoneDrinkID.
    public let drinkID: String?
    /// HKMetadataKeyFoodType.
    public let drinkName: String?
    /// SayoneVolumeML.
    public let volumeML: Int?
    /// SayoneOrigin.
    public let origin: DeviceKind?

    public init(date: Date, waterML: Double, entryID: UUID?, drinkID: String?, drinkName: String?, volumeML: Int?, origin: DeviceKind?) {
        self.date = date
        self.waterML = waterML
        self.entryID = entryID
        self.drinkID = drinkID
        self.drinkName = drinkName
        self.volumeML = volumeML
        self.origin = origin
    }
}
