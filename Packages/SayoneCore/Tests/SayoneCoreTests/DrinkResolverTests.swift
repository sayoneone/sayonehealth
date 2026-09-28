import Foundation
import XCTest
@testable import SayoneCore

final class DrinkResolverTests: XCTestCase {
    private func customDrink(id: String = "custom-1", name: String? = "Kvass", archived: Bool = false) -> Drink {
        Drink(id: id, builtIn: nil, customName: name, symbol: "leaf.fill", tint: .purple, hydrationFactor: 0.8,
              per100ML: NutrientsPer100ML(energyKcal: 27), defaultVolumeML: 330, isArchived: archived)
    }

    func testCatalogDrinkWins() {
        var catalog = Catalog.makeDefault()
        catalog.drinks.append(customDrink())
        let r = DrinkResolver.resolve(drinkID: "custom-1", in: catalog, fallbackName: "Ignored")
        XCTAssertTrue(r.isKnown)
        XCTAssertEqual(r.drink, customDrink())
    }

    func testArchivedCatalogDrinkStillResolves() {
        var catalog = Catalog.makeDefault()
        catalog.drinks.append(customDrink(archived: true))
        let r = DrinkResolver.resolve(drinkID: "custom-1", in: catalog, fallbackName: "")
        XCTAssertTrue(r.isKnown)
        XCTAssertTrue(r.drink.isArchived)
    }

    func testEditedBuiltInComesFromCatalog() {
        var catalog = Catalog.makeDefault()
        catalog.drinks[0].hydrationFactor = 0.9
        let r = DrinkResolver.resolve(drinkID: "water", in: catalog, fallbackName: "")
        XCTAssertTrue(r.isKnown)
        XCTAssertEqual(r.drink.hydrationFactor, 0.9)
    }

    func testBuiltInFallbackWhenCatalogLacksIt() {
        let catalog = Catalog(version: 1, revision: 0, updatedAt: Date(), drinks: [], presets: [], settings: UserSettings())
        let r = DrinkResolver.resolve(drinkID: "tea", in: catalog, fallbackName: "x")
        XCTAssertTrue(r.isKnown)
        XCTAssertEqual(r.drink, BuiltInCatalog.drink(.tea))
    }

    func testUnknownDrinkKeepsItsOwnName() {
        let r = DrinkResolver.resolve(drinkID: "custom-gone", in: Catalog.makeDefault(), fallbackName: "Kombucha")
        XCTAssertFalse(r.isKnown)
        XCTAssertEqual(r.drink, Drink.unknown(id: "custom-gone", name: "Kombucha"))
        XCTAssertEqual(r.drink.id, "custom-gone")
        XCTAssertNil(r.drink.builtIn)
        XCTAssertEqual(r.drink.customName, "Kombucha")
        XCTAssertEqual(r.drink.symbol, "cup.and.saucer.fill")
        XCTAssertEqual(r.drink.tint, .gray)
        XCTAssertEqual(r.drink.hydrationFactor, 1.0)
        XCTAssertEqual(r.drink.per100ML, NutrientsPer100ML())
        XCTAssertEqual(r.drink.defaultVolumeML, 250)
        XCTAssertFalse(r.drink.isArchived)
        XCTAssertEqual(r.drink.name(.en), "Kombucha")
    }

    func testUnknownWithoutNameIsGenericDrink() {
        let drink = Drink.unknown(id: "x", name: "")
        XCTAssertNil(drink.customName)
        XCTAssertNil(Drink.unknown(id: "x", name: nil).customName)
        XCTAssertNil(Drink.unknown(id: "x", name: "   ").customName)
        XCTAssertEqual(drink.name(.ru), "Напиток")
        XCTAssertEqual(drink.name(.en), "Drink")
        XCTAssertEqual(drink.accusative(.ru), "напиток")
        XCTAssertEqual(drink.accusative(.en), "drink")
    }

    func testDrinkNames() {
        XCTAssertEqual(BuiltInCatalog.drink(.colaZero).name(.ru), "Кола без сахара")
        XCTAssertEqual(BuiltInCatalog.drink(.colaZero).accusative(.ru), "колу без сахара")
        XCTAssertEqual(BuiltInCatalog.drink(.colaZero).name(.en), "Cola Zero")
        XCTAssertEqual(BuiltInCatalog.drink(.colaZero).accusative(.en), "cola zero")
        XCTAssertEqual(customDrink(name: "  Квас  ").name(.ru), "Квас")
        XCTAssertEqual(customDrink(name: "  Квас  ").accusative(.ru), "Квас")
        XCTAssertEqual(customDrink(name: " ").name(.en), "Drink")
        var blankBuiltIn = BuiltInCatalog.drink(.water)
        blankBuiltIn.customName = "   "
        XCTAssertEqual(blankBuiltIn.name(.ru), "Вода")
        XCTAssertEqual(blankBuiltIn.accusative(.ru), "воду")
    }

    func testAppLanguageFromPreferredLocalizations() {
        XCTAssertEqual(AppLanguage(preferredLocalizations: ["ru"]), .ru)
        XCTAssertEqual(AppLanguage(preferredLocalizations: ["ru-RU", "en"]), .ru)
        XCTAssertEqual(AppLanguage(preferredLocalizations: ["en", "ru"]), .en)
        XCTAssertEqual(AppLanguage(preferredLocalizations: ["de"]), .en)
        XCTAssertEqual(AppLanguage(preferredLocalizations: []), .en)
    }

    func testForwardCompatibleEnums() throws {
        let decoder = CoreJSON.decoder()
        XCTAssertEqual(try decoder.decode([DrinkTint].self, from: Data(#"["magenta","red"]"#.utf8)), [.blue, .red])
        XCTAssertEqual(try decoder.decode([LogSource].self, from: Data(#"["shortcut","siri"]"#.utf8)), [.app, .siri])
        XCTAssertEqual(String(decoding: try CoreJSON.encoder().encode([DrinkTint.teal]), as: UTF8.self), #"["teal"]"#)
        XCTAssertEqual(String(decoding: try CoreJSON.encoder().encode([LogSource.deepLink]), as: UTF8.self), #"["deepLink"]"#)
    }

    func testResolvedDrinkInit() {
        let r = ResolvedDrink(drink: BuiltInCatalog.drink(.milk), isKnown: true)
        XCTAssertEqual(r.drink.id, "milk")
        XCTAssertTrue(r.isKnown)
    }
}
