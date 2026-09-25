import Foundation

/// HealthKit metadata keys and sync identifiers (§4.0).
public enum HealthMetadata {
    public static let entryIDKey: String = "SayoneEntryID"
    public static let drinkIDKey: String = "SayoneDrinkID"
    public static let volumeKey: String = "SayoneVolumeML"
    public static let originKey: String = "SayoneOrigin"
    public static let syncVersion: Int = 1

    /// "\(entryID.uuidString).\(component.rawValue)", e.g. "8C1E…9A.water".
    public static func syncIdentifier(entryID: UUID, component: HealthComponent) -> String {
        "\(entryID.uuidString).\(component.rawValue)"
    }

    /// Smallest amount worth a sample: water 1 ml, caffeine 0.5 mg, energy 0.5 kcal, sugar 0.1 g.
    public static func minimumAmount(_ component: HealthComponent) -> Double {
        switch component {
        case .water: return 1
        case .caffeine: return 0.5
        case .energy: return 0.5
        case .sugar: return 0.1
        }
    }
}

/// A custom metadata value; HealthGateway maps it to String or NSNumber.
public enum MetadataValue: Hashable, Sendable {
    case string(String)
    case number(Double)
}

/// One HealthKit quantity sample to write, as plain data.
public struct HealthSampleSpec: Hashable, Sendable {
    public let component: HealthComponent
    /// Canonical unit: mL | mg | kcal | g.
    public let amount: Double
    /// start == end == entry.date.
    public let date: Date
    public let syncIdentifier: String
    public let syncVersion: Int
    /// entry.drinkName.
    public let foodType: String
    /// SayoneEntryID (.string uuidString), SayoneDrinkID, SayoneVolumeML (.number), SayoneOrigin (.string rawValue).
    public let custom: [String: MetadataValue]

    public init(component: HealthComponent, amount: Double, date: Date, syncIdentifier: String, syncVersion: Int,
                foodType: String, custom: [String: MetadataValue]) {
        self.component = component
        self.amount = amount
        self.date = date
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.foodType = foodType
        self.custom = custom
    }
}

public enum HealthSamplePlan {
    /// Water always first (if >= minimum); nutrients only if includeNutrients and amount >= minimum.
    /// Order = HealthComponent.allCases.
    public static func components(for entry: IntakeEntry, includeNutrients: Bool) -> [HealthComponent] {
        HealthComponent.allCases.filter { component in
            if component != .water && !includeNutrients { return false }
            let amount = entry.nutrients.amount(of: component)
            return amount.isFinite && amount >= HealthMetadata.minimumAmount(component)
        }
    }

    public static func specs(for entry: IntakeEntry, includeNutrients: Bool) -> [HealthSampleSpec] {
        let custom: [String: MetadataValue] = [
            HealthMetadata.entryIDKey: .string(entry.id.uuidString),
            HealthMetadata.drinkIDKey: .string(entry.drinkID),
            HealthMetadata.volumeKey: .number(Double(entry.volumeML)),
            HealthMetadata.originKey: .string(entry.origin.rawValue)
        ]
        return components(for: entry, includeNutrients: includeNutrients).map { component in
            HealthSampleSpec(component: component,
                             amount: entry.nutrients.amount(of: component),
                             date: entry.date,
                             syncIdentifier: HealthMetadata.syncIdentifier(entryID: entry.id, component: component),
                             syncVersion: HealthMetadata.syncVersion,
                             foodType: entry.drinkName,
                             custom: custom)
        }
    }
}
