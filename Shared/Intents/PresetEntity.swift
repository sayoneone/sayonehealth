import AppIntents
import SayoneCore

/// One drink button (preset) as an App Intents entity. It is the configuration value of the
/// Quick Log widget and of the iOS control. The values are copied from `PresetDisplay`, so a
/// configured widget keeps working even if the preset is later removed from the catalog.
struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink Button")
    static let defaultQuery = PresetQuery()
    let id: String
    let drinkID: String
    let drinkName: String
    let symbol: String
    let tintRaw: String
    let volumeML: Int
    var displayRepresentation: DisplayRepresentation {
        // Title carries the volume ("Вода · 500 мл"), so two water presets are distinguishable in the
        // configured widget/control row and in the watchOS 26 face editor, not only inside the picker.
        DisplayRepresentation(title: "\(drinkName) · \(VolumeText.short(volumeML))",
                              subtitle: nil,
                              image: DisplayRepresentation.Image(systemName: symbol))
    }
    init(_ p: PresetDisplay) {
        id = p.id; drinkID = p.drinkID; drinkName = p.drinkName; symbol = p.symbol; tintRaw = p.tint.rawValue; volumeML = p.volumeML
    }
    var display: PresetDisplay {
        PresetDisplay(id: id, drinkID: drinkID, drinkName: drinkName, symbol: symbol,
                      tint: DrinkTint(rawValue: tintRaw) ?? .blue, volumeML: volumeML)
    }
}

/// Reads the presets from the App Group catalog; runs in whichever process asks (app or widget).
struct PresetQuery: EntityQuery {
    init() {}
    func entities(for identifiers: [PresetEntity.ID]) async throws -> [PresetEntity] {
        PresetDisplays.all().filter { identifiers.contains($0.id) }.map(PresetEntity.init)
    }
    func suggestedEntities() async throws -> [PresetEntity] {
        PresetDisplays.all().map(PresetEntity.init)
    }
    func defaultResult() async -> PresetEntity? {
        PresetDisplays.all().first.map(PresetEntity.init)
    }
}
