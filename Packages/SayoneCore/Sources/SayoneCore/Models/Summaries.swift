import Foundation

/// Today's total and everything the widgets, app and Siri say about it.
public struct TodaySummary: Hashable, Sendable {
    /// Displayed total.
    public var waterML: Int
    public var goalML: Int
    public var localWaterML: Int
    public var externalWaterML: Int
    public var otherDeviceWaterML: Int
    /// Local entries with health == .pending (any day).
    public var pendingCount: Int
    /// Newest visible local entry today.
    public var lastLocal: IntakeEntry?
    /// lastLocal.date + UndoPolicy.widgetWindow, only if > now.
    public var undoAvailableUntil: Date?
    /// snapshot.readAt if it is today's snapshot.
    public var healthReadAt: Date?

    public init(waterML: Int, goalML: Int, localWaterML: Int, externalWaterML: Int, otherDeviceWaterML: Int,
                pendingCount: Int, lastLocal: IntakeEntry?, undoAvailableUntil: Date?, healthReadAt: Date?) {
        self.waterML = waterML
        self.goalML = goalML
        self.localWaterML = localWaterML
        self.externalWaterML = externalWaterML
        self.otherDeviceWaterML = otherDeviceWaterML
        self.pendingCount = pendingCount
        self.lastLocal = lastLocal
        self.undoAvailableUntil = undoAvailableUntil
        self.healthReadAt = healthReadAt
    }

    /// min(1, max(0, waterML / max(goalML, 1))).
    public var progress: Double {
        min(1, max(0, Double(waterML) / Double(max(goalML, 1))))
    }

    /// 1200 of 2000 ml; everything else zero or nil. Used by widget placeholders and previews.
    public static let placeholder: TodaySummary = TodaySummary(waterML: 1200, goalML: 2000, localWaterML: 0, externalWaterML: 0,
                                                 otherDeviceWaterML: 0, pendingCount: 0, lastLocal: nil,
                                                 undoAvailableUntil: nil, healthReadAt: nil)
}

/// Water total of one calendar day.
public struct DayTotal: Hashable, Identifiable, Sendable {
    public let dayStart: Date
    public let waterML: Int

    public var id: Date { dayStart }

    public init(dayStart: Date, waterML: Int) {
        self.dayStart = dayStart
        self.waterML = waterML
    }
}

/// One row of today's list: a local entry or a sample our app wrote on the other device.
public struct TodayRow: Hashable, Identifiable, Sendable {
    /// Entry id.
    public let id: UUID
    public let date: Date
    public let drinkName: String
    /// nil for other-device rows.
    public let symbol: String?
    public let volumeML: Int
    public let waterML: Double
    public let origin: DeviceKind?
    /// true = in this device's journal.
    public let isLocal: Bool
    /// local && health == .pending.
    public let isPendingHealth: Bool

    public init(id: UUID, date: Date, drinkName: String, symbol: String?, volumeML: Int, waterML: Double,
                origin: DeviceKind?, isLocal: Bool, isPendingHealth: Bool) {
        self.id = id
        self.date = date
        self.drinkName = drinkName
        self.symbol = symbol
        self.volumeML = volumeML
        self.waterML = waterML
        self.origin = origin
        self.isLocal = isLocal
        self.isPendingHealth = isPendingHealth
    }
}
