import AppIntents
import SayoneCore

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    @Parameter(title: "Amount", default: .glass) var amount: WaterAmount
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let o = await DrinkLogger.log(drinkID: BuiltInDrink.water.rawValue, volumeML: amount.milliliters, source: .siri)
        let text = SiriText.logged(o)
        return .result(dialog: "\(text)")
    }
}
