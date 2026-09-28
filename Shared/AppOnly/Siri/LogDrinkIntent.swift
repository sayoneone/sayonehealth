import AppIntents
import SayoneCore

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    @Parameter(title: "Drink") var drink: DrinkEntity
    @Parameter(title: "Volume (ml)") var volumeML: Int?
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ml = volumeML ?? drink.defaultVolumeML
        let o = await DrinkLogger.log(drinkID: drink.id, volumeML: ml, fallbackName: drink.name, source: .siri)
        let text = SiriText.logged(o)
        return .result(dialog: "\(text)")
    }
}
