import Foundation

/// A drink in the catalog: built-in (`id == builtIn.rawValue`) or user-made (`id == "custom-<UUID>"`).
public struct Drink: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var builtIn: BuiltInDrink?
    public var customName: String?
    /// SF Symbol name.
    public var symbol: String
    public var tint: DrinkTint
    /// Share of the volume written as dietaryWater (`NutrientMath.hydrationRange`).
    public var hydrationFactor: Double
    public var per100ML: NutrientsPer100ML
    public var defaultVolumeML: Int
    public var isArchived: Bool

    public init(id: String, builtIn: BuiltInDrink?, customName: String?, symbol: String, tint: DrinkTint,
                hydrationFactor: Double, per100ML: NutrientsPer100ML, defaultVolumeML: Int, isArchived: Bool = false) {
        self.id = id
        self.builtIn = builtIn
        self.customName = customName
        self.symbol = symbol
        self.tint = tint
        self.hydrationFactor = hydrationFactor
        self.per100ML = per100ML
        self.defaultVolumeML = defaultVolumeML
        self.isArchived = isArchived
    }

    /// Trimmed custom name, or nil when it is missing or blank.
    var trimmedCustomName: String? {
        guard let raw = customName else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Nominative display name: custom name, else the built-in name, else the generic "Drink".
    public func name(_ lang: AppLanguage) -> String {
        if let custom = trimmedCustomName { return custom }
        if let builtIn = builtIn { return Phrasebook.drinkName(builtIn, lang) }
        return Phrasebook.genericDrink(lang)
    }

    /// Accusative form for Siri phrases: custom name, else the built-in accusative, else "drink"/"напиток".
    public func accusative(_ lang: AppLanguage) -> String {
        if let custom = trimmedCustomName { return custom }
        if let builtIn = builtIn { return Phrasebook.drinkAccusative(builtIn, lang) }
        return Phrasebook.genericDrink(lang).lowercased()
    }

    /// A stand-in for a drink id that neither the catalog nor the built-ins know.
    /// It keeps the caller's name so the entry is never silently logged as water.
    public static func unknown(id: String, name: String?) -> Drink {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Drink(id: id,
                     builtIn: nil,
                     customName: trimmed.isEmpty ? nil : trimmed,
                     symbol: "cup.and.saucer.fill",
                     tint: .gray,
                     hydrationFactor: 1.0,
                     per100ML: NutrientsPer100ML(),
                     defaultVolumeML: 250,
                     isArchived: false)
    }
}
