import Foundation

/// Nutrient content per 100 ml of a drink.
public struct NutrientsPer100ML: Codable, Hashable, Sendable {
    public var caffeineMG: Double
    public var energyKcal: Double
    public var sugarG: Double

    public init(caffeineMG: Double = 0, energyKcal: Double = 0, sugarG: Double = 0) {
        self.caffeineMG = caffeineMG
        self.energyKcal = energyKcal
        self.sugarG = sugarG
    }
}

/// Absolute amounts of one logged drink, in canonical units (mL, mg, kcal, g).
public struct Nutrients: Codable, Hashable, Sendable {
    public var waterML: Double
    public var caffeineMG: Double
    public var energyKcal: Double
    public var sugarG: Double

    public init(waterML: Double = 0, caffeineMG: Double = 0, energyKcal: Double = 0, sugarG: Double = 0) {
        self.waterML = waterML
        self.caffeineMG = caffeineMG
        self.energyKcal = energyKcal
        self.sugarG = sugarG
    }

    public func amount(of component: HealthComponent) -> Double {
        switch component {
        case .water: return waterML
        case .caffeine: return caffeineMG
        case .energy: return energyKcal
        case .sugar: return sugarG
        }
    }
}
