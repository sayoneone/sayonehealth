import HealthKit
import SayoneCore

/// The HealthKit type and unit table. Every unit used in the project comes from `unit(_:)`.
enum HKDrinkTypes {
    static func type(_ c: HealthComponent) -> HKQuantityType {
        switch c {
        case .water: return HKQuantityType(.dietaryWater)
        case .caffeine: return HKQuantityType(.dietaryCaffeine)
        case .energy: return HKQuantityType(.dietaryEnergyConsumed)
        case .sugar: return HKQuantityType(.dietarySugar)
        }
    }

    static func unit(_ c: HealthComponent) -> HKUnit {
        switch c {
        case .water: return HKUnit.literUnit(with: .milli)
        case .caffeine: return HKUnit.gramUnit(with: .milli)
        case .energy: return HKUnit.kilocalorie()
        case .sugar: return HKUnit.gram()
        }
    }

    /// Write access: water, caffeine, energy, sugar. Quantity types only (never a correlation type).
    static let share: Set<HKSampleType> = [
        HKDrinkTypes.type(.water),
        HKDrinkTypes.type(.caffeine),
        HKDrinkTypes.type(.energy),
        HKDrinkTypes.type(.sugar)
    ]

    /// Read access: water only (totals from every source, including the other device).
    static let read: Set<HKObjectType> = [
        HKDrinkTypes.type(.water)
    ]
}
