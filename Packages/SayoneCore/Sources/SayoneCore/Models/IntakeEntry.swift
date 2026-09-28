import Foundation

/// One logged drink on THIS device. Stored as `Journal/<id>.json`.
public struct IntakeEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Whole milliseconds (IntakeFactory rounds).
    public let date: Date
    public let drinkID: String
    /// Localized at log time; HealthKit FoodType.
    public let drinkName: String
    public let symbol: String
    /// Poured volume.
    public let volumeML: Int
    /// Computed at log time.
    public let nutrients: Nutrients
    public let origin: DeviceKind
    public let source: LogSource
    public var health: HealthSyncStatus
    public var healthSavedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID, date: Date, drinkID: String, drinkName: String, symbol: String, volumeML: Int,
                nutrients: Nutrients, origin: DeviceKind, source: LogSource,
                health: HealthSyncStatus = .pending, healthSavedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.date = date
        self.drinkID = drinkID
        self.drinkName = drinkName
        self.symbol = symbol
        self.volumeML = volumeML
        self.nutrients = nutrients
        self.origin = origin
        self.source = source
        self.health = health
        self.healthSavedAt = healthSavedAt
        self.deletedAt = deletedAt
    }

    /// Counted and listed: `.pending` or `.saved`.
    public var isVisible: Bool { health == .pending || health == .saved }
}
