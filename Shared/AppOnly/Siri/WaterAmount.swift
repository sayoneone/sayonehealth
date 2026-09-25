import AppIntents
import SayoneCore

/// Spoken water amounts for `LogWaterIntent`. The ru titles (стакан / банку / пол-литра / литр)
/// come from Localizable.xcstrings and are matched literally by Siri on the watch (§7).
enum WaterAmount: String, AppEnum, CaseIterable {
    case glass, can, halfLiter, liter
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Amount")
    static let caseDisplayRepresentations: [WaterAmount: DisplayRepresentation] = [
        .glass: DisplayRepresentation(title: "a glass", subtitle: nil, image: nil, synonyms: ["glass", "one glass"]),
        .can: DisplayRepresentation(title: "a can", subtitle: nil, image: nil, synonyms: ["can", "one can"]),
        .halfLiter: DisplayRepresentation(title: "half a liter", subtitle: nil, image: nil, synonyms: ["half a litre", "0.5 liters"]),
        .liter: DisplayRepresentation(title: "a liter", subtitle: nil, image: nil, synonyms: ["a litre", "one liter"])
    ]
    var milliliters: Int {
        switch self {
        case .glass: return 250
        case .can: return 330
        case .halfLiter: return 500
        case .liter: return 1000
        }
    }
}
