import Foundation

/// Clamps and the nutrient computation of one logged drink.
public enum NutrientMath {
    public static let volumeRange: ClosedRange<Int> = 10...5000
    public static let hydrationRange: ClosedRange<Double> = 0.1...1.0

    public static func clampVolume(_ ml: Int) -> Int {
        min(max(ml, volumeRange.lowerBound), volumeRange.upperBound)
    }

    /// NaN becomes 1.0 (the built-in default); everything else is clamped to 0.1...1.0.
    public static func clampHydration(_ factor: Double) -> Double {
        guard !factor.isNaN else { return hydrationRange.upperBound }
        return min(max(factor, hydrationRange.lowerBound), hydrationRange.upperBound)
    }

    /// Volume and hydration are clamped first; every value is rounded to 0.1.
    public static func nutrients(for drink: Drink, volumeML: Int) -> Nutrients {
        let volume = Double(clampVolume(volumeML))
        let hydration = clampHydration(drink.hydrationFactor)
        let per100 = drink.per100ML
        return Nutrients(waterML: roundTenth(volume * hydration),
                         caffeineMG: roundTenth(per100.caffeineMG * volume / 100),
                         energyKcal: roundTenth(per100.energyKcal * volume / 100),
                         sugarG: roundTenth(per100.sugarG * volume / 100))
    }

    static func roundTenth(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return (x * 10).rounded() / 10
    }

    /// `Int(x.rounded())` that never traps (non-finite → 0, clamped to the 32-bit range for arm64_32).
    static func safeInt(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        let r = x.rounded()
        if r >= Double(Int32.max) { return Int(Int32.max) }
        if r <= Double(Int32.min) { return Int(Int32.min) }
        return Int(r)
    }
}
