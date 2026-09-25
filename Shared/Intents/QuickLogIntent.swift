import AppIntents
import SayoneCore

/// One-tap log used by widget buttons and the iOS control. Every parameter is a primitive with a
/// default, because widgets and controls never resolve parameters. `perform()` runs in the widget
/// extension process and awaits the journal write (and the Health save attempt) before returning,
/// so the timeline reload that follows already sees the new entry.
struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Log"
    static let isDiscoverable: Bool = false
    @Parameter(title: "Drink ID", default: "water") var drinkID: String
    @Parameter(title: "Volume (ml)", default: 250) var volumeML: Int
    @Parameter(title: "Drink Name", default: "") var drinkName: String
    init() {}
    init(drinkID: String, volumeML: Int, drinkName: String) {
        self.drinkID = drinkID
        self.volumeML = volumeML
        self.drinkName = drinkName
    }
    init(_ p: PresetDisplay) { self.init(drinkID: p.drinkID, volumeML: p.volumeML, drinkName: p.drinkName) }
    func perform() async throws -> some IntentResult {
        _ = await DrinkLogger.log(drinkID: drinkID, volumeML: volumeML, fallbackName: drinkName, source: .widget)
        return .result()
    }
}
