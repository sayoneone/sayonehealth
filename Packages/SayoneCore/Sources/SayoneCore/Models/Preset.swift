import Foundation

/// A one-tap button: a drink and a volume.
public struct Preset: Codable, Hashable, Identifiable, Sendable {
    /// Built-in "water-250" …; user "preset-<UUID>".
    public var id: String
    public var drinkID: String
    public var volumeML: Int

    public init(id: String, drinkID: String, volumeML: Int) {
        self.id = id
        self.drinkID = drinkID
        self.volumeML = volumeML
    }
}

/// A preset together with its drink.
public struct ResolvedPreset: Hashable, Identifiable, Sendable {
    public let preset: Preset
    public let drink: Drink

    public var id: String { preset.id }

    public init(preset: Preset, drink: Drink) {
        self.preset = preset
        self.drink = drink
    }
}

/// Everything a widget, control or button needs to show and log a preset, already localized.
public struct PresetDisplay: Codable, Hashable, Identifiable, Sendable {
    /// Preset id.
    public let id: String
    public let drinkID: String
    /// Localized when built, e.g. "Кола без сахара".
    public let drinkName: String
    public let symbol: String
    public let tint: DrinkTint
    public let volumeML: Int

    public init(id: String, drinkID: String, drinkName: String, symbol: String, tint: DrinkTint, volumeML: Int) {
        self.id = id
        self.drinkID = drinkID
        self.drinkName = drinkName
        self.symbol = symbol
        self.tint = tint
        self.volumeML = volumeML
    }

    public init(_ resolved: ResolvedPreset, lang: AppLanguage) {
        self.init(id: resolved.preset.id,
                  drinkID: resolved.preset.drinkID,
                  drinkName: resolved.drink.name(lang),
                  symbol: resolved.drink.symbol,
                  tint: resolved.drink.tint,
                  volumeML: resolved.preset.volumeML)
    }

    /// drinkName + " · " + VolumeFormat.short(volumeML, lang), e.g. "Вода · 250 мл".
    public func localizedTitle(_ lang: AppLanguage) -> String {
        drinkName + " · " + VolumeFormat.short(volumeML, lang)
    }

    /// Water 250 ml, built without any I/O. Used by placeholders and when the catalog has no presets.
    public static func builtInFallback(_ lang: AppLanguage) -> PresetDisplay {
        let water = BuiltInCatalog.drink(.water)
        return PresetDisplay(id: BuiltInCatalog.fallbackPresetID,
                             drinkID: BuiltInCatalog.fallbackDrinkID,
                             drinkName: water.name(lang),
                             symbol: water.symbol,
                             tint: water.tint,
                             volumeML: 250)
    }
}
