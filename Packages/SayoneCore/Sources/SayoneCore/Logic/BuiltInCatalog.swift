import Foundation

/// The built-in drinks and default presets (§5.1 table). Values are approximate and editable.
public enum BuiltInCatalog {
    public static let fallbackDrinkID: String = "water"
    public static let fallbackPresetID: String = "water-250"

    /// SF Symbols offered for custom drinks.
    public static let customSymbols: [String] = [
        "drop.fill", "cup.and.saucer.fill", "mug.fill", "wineglass.fill", "waterbottle.fill",
        "takeoutbag.and.cup.and.straw.fill", "bubbles.and.sparkles.fill", "leaf.fill", "flame.fill",
        "bolt.fill", "birthday.cake.fill", "star.fill"
    ]

    public static func drink(_ kind: BuiltInDrink) -> Drink {
        switch kind {
        case .water:
            return make(kind, symbol: "drop.fill", tint: .blue,
                        per100: NutrientsPer100ML(), defaultVolumeML: 250)
        case .sparklingWater:
            return make(kind, symbol: "bubbles.and.sparkles.fill", tint: .teal,
                        per100: NutrientsPer100ML(), defaultVolumeML: 330)
        case .colaZero:
            return make(kind, symbol: "takeoutbag.and.cup.and.straw.fill", tint: .red,
                        per100: NutrientsPer100ML(caffeineMG: 9.6, energyKcal: 0.3, sugarG: 0), defaultVolumeML: 330)
        case .coffee:
            return make(kind, symbol: "cup.and.saucer.fill", tint: .brown,
                        per100: NutrientsPer100ML(caffeineMG: 40, energyKcal: 1, sugarG: 0), defaultVolumeML: 200)
        case .tea:
            return make(kind, symbol: "mug.fill", tint: .green,
                        per100: NutrientsPer100ML(caffeineMG: 20, energyKcal: 1, sugarG: 0), defaultVolumeML: 250)
        case .juice:
            return make(kind, symbol: "wineglass.fill", tint: .orange,
                        per100: NutrientsPer100ML(caffeineMG: 0, energyKcal: 45, sugarG: 9), defaultVolumeML: 250)
        case .milk:
            return make(kind, symbol: "waterbottle.fill", tint: .gray,
                        per100: NutrientsPer100ML(caffeineMG: 0, energyKcal: 52, sugarG: 4.7), defaultVolumeML: 250)
        }
    }

    /// `BuiltInDrink(rawValue: id).map(drink(_:))`.
    public static func drink(id: String) -> Drink? {
        BuiltInDrink(rawValue: id).map { drink($0) }
    }

    /// In `BuiltInDrink.allCases` order.
    public static var allDrinks: [Drink] {
        BuiltInDrink.allCases.map { drink($0) }
    }

    /// water-250, water-500, colaZero-330, coffee-200, tea-250.
    public static var defaultPresets: [Preset] {
        [
            Preset(id: "water-250", drinkID: BuiltInDrink.water.rawValue, volumeML: 250),
            Preset(id: "water-500", drinkID: BuiltInDrink.water.rawValue, volumeML: 500),
            Preset(id: "colaZero-330", drinkID: BuiltInDrink.colaZero.rawValue, volumeML: 330),
            Preset(id: "coffee-200", drinkID: BuiltInDrink.coffee.rawValue, volumeML: 200),
            Preset(id: "tea-250", drinkID: BuiltInDrink.tea.rawValue, volumeML: 250)
        ]
    }

    private static func make(_ kind: BuiltInDrink, symbol: String, tint: DrinkTint,
                             per100: NutrientsPer100ML, defaultVolumeML: Int) -> Drink {
        Drink(id: kind.rawValue, builtIn: kind, customName: nil, symbol: symbol, tint: tint,
              hydrationFactor: 1.0, per100ML: per100, defaultVolumeML: defaultVolumeML, isArchived: false)
    }
}
