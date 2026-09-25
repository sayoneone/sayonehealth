import Foundation
import AppIntents
import SayoneCore

/// A drink from this device's catalog, spoken as the `${drink}` parameter of `LogDrinkIntent`.
/// Title = nominative name («Кола без сахара»); synonyms = accusative («колу без сахара») and lowercased name.
struct DrinkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink")
    static let defaultQuery = DrinkQuery()
    let id: String
    let name: String
    let accusative: String
    let symbol: String
    let defaultVolumeML: Int
    /// Names in every supported language (nominative, accusative, lowercased): Siri's language can differ
    /// from the UI language, e.g. English Siri on a Russian iPhone must still match "Cola Zero".
    let spokenNames: [String]
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: nil,
                              image: DisplayRepresentation.Image(systemName: symbol),
                              synonyms: spokenNames.map { spoken -> LocalizedStringResource in "\(spoken)" })
    }
    init(_ drink: Drink) {
        id = drink.id; name = drink.displayName; accusative = drink.accusativeName
        symbol = drink.symbol; defaultVolumeML = drink.defaultVolumeML
        var names: [String] = []
        for lang in AppLanguage.allCases {
            for spoken in [drink.name(lang), drink.accusative(lang), drink.name(lang).lowercased()]
            where !spoken.isEmpty && !names.contains(spoken) && spoken != drink.displayName {
                names.append(spoken)
            }
        }
        spokenNames = names
    }
}

struct DrinkQuery: EntityStringQuery {
    init() {}

    /// Catalog drinks by id, archived ones included (an old shortcut may still reference them).
    func entities(for identifiers: [DrinkEntity.ID]) async throws -> [DrinkEntity] {
        let catalog = AppGroup.catalog.load()
        var result: [DrinkEntity] = []
        for id in identifiers {
            if let drink = catalog.drink(id: id) ?? BuiltInCatalog.drink(id: id) {
                result.append(DrinkEntity(drink))
            }
        }
        return result
    }

    /// Values for the parameterized phrases. Water is excluded so «Запиши воду» maps only to LogWaterIntent.
    func suggestedEntities() async throws -> [DrinkEntity] {
        let drinks = AppGroup.catalog.load().activeDrinks
        return drinks
            .filter { drink in drink.id != BuiltInDrink.water.rawValue }
            .map { drink in DrinkEntity(drink) }
    }

    /// Case-insensitive search over every active drink (water included), in both languages.
    func entities(matching string: String) async throws -> [DrinkEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let drinks = AppGroup.catalog.load().activeDrinks
        if needle.isEmpty {
            return drinks.map { drink in DrinkEntity(drink) }
        }
        let direct = drinks.filter { drink in
            DrinkQuery.names(of: drink).contains { name in name.localizedCaseInsensitiveContains(needle) }
        }
        if !direct.isEmpty {
            return direct.map { drink in DrinkEntity(drink) }
        }
        // Longer utterances ("колу без сахара, пожалуйста"): the spoken text contains a drink name.
        let spoken = needle.lowercased()
        let reverse = drinks.filter { drink in
            DrinkQuery.names(of: drink).contains { name in name.count >= 3 && spoken.contains(name.lowercased()) }
        }
        return reverse.map { drink in DrinkEntity(drink) }
    }

    private static func names(of drink: Drink) -> [String] {
        var names: [String] = []
        for lang in AppLanguage.allCases {
            names.append(drink.name(lang))
            names.append(drink.accusative(lang))
        }
        return names
    }
}
