import Foundation

/// A drink looked up by id, and whether the id was known.
public struct ResolvedDrink: Hashable, Sendable {
    public let drink: Drink
    /// false => `Drink.unknown` was used.
    public let isKnown: Bool

    public init(drink: Drink, isKnown: Bool) {
        self.drink = drink
        self.isKnown = isKnown
    }
}

public enum DrinkResolver {
    /// catalog.drink(id:) (archived included) → BuiltInCatalog.drink(id:) → Drink.unknown(id:, name: fallbackName)
    public static func resolve(drinkID: String, in catalog: Catalog, fallbackName: String) -> ResolvedDrink {
        if let drink = catalog.drink(id: drinkID) {
            return ResolvedDrink(drink: drink, isKnown: true)
        }
        if let drink = BuiltInCatalog.drink(id: drinkID) {
            return ResolvedDrink(drink: drink, isKnown: true)
        }
        return ResolvedDrink(drink: Drink.unknown(id: drinkID, name: fallbackName), isKnown: false)
    }
}
