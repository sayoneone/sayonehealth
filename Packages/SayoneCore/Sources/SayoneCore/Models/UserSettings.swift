import Foundation

/// Settings that travel with the catalog from the phone to the watch.
public struct UserSettings: Codable, Hashable, Sendable {
    public static let goalRange: ClosedRange<Int> = 500...6000

    /// Default 2000.
    public var dailyGoalML: Int
    /// Default true: caffeine, energy and sugar samples are written next to water.
    public var writeNutrients: Bool

    public init(dailyGoalML: Int = 2000, writeNutrients: Bool = true) {
        self.dailyGoalML = dailyGoalML
        self.writeNutrients = writeNutrients
    }

    static func clampGoal(_ ml: Int) -> Int {
        min(max(ml, goalRange.lowerBound), goalRange.upperBound)
    }
}
