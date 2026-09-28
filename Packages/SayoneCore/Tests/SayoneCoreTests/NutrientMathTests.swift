import Foundation
import XCTest
@testable import SayoneCore

final class NutrientMathTests: XCTestCase {
    func testRanges() {
        XCTAssertEqual(NutrientMath.volumeRange, 10...5000)
        XCTAssertEqual(NutrientMath.hydrationRange, 0.1...1.0)
    }

    func testClampVolume() {
        XCTAssertEqual(NutrientMath.clampVolume(-5), 10)
        XCTAssertEqual(NutrientMath.clampVolume(5), 10)
        XCTAssertEqual(NutrientMath.clampVolume(10), 10)
        XCTAssertEqual(NutrientMath.clampVolume(250), 250)
        XCTAssertEqual(NutrientMath.clampVolume(5000), 5000)
        XCTAssertEqual(NutrientMath.clampVolume(6000), 5000)
        XCTAssertEqual(NutrientMath.clampVolume(Int.max), 5000)
    }

    func testClampHydration() {
        XCTAssertEqual(NutrientMath.clampHydration(0), 0.1)
        XCTAssertEqual(NutrientMath.clampHydration(-1), 0.1)
        XCTAssertEqual(NutrientMath.clampHydration(0.5), 0.5)
        XCTAssertEqual(NutrientMath.clampHydration(1.5), 1.0)
        XCTAssertEqual(NutrientMath.clampHydration(.infinity), 1.0)
        XCTAssertEqual(NutrientMath.clampHydration(.nan), 1.0)
    }

    func testCoffeeNutrients() {
        let n = NutrientMath.nutrients(for: BuiltInCatalog.drink(.coffee), volumeML: 200)
        XCTAssertEqual(n, Nutrients(waterML: 200, caffeineMG: 80, energyKcal: 2, sugarG: 0))
    }

    func testColaZeroNutrientsAreRoundedToTenths() {
        let n = NutrientMath.nutrients(for: BuiltInCatalog.drink(.colaZero), volumeML: 330)
        XCTAssertEqual(n.waterML, 330)
        XCTAssertEqual(n.caffeineMG, 31.7)   // 31.68
        XCTAssertEqual(n.energyKcal, 1.0)    // 0.99
        XCTAssertEqual(n.sugarG, 0)
    }

    func testMilkAndJuice() {
        let milk = NutrientMath.nutrients(for: BuiltInCatalog.drink(.milk), volumeML: 250)
        XCTAssertEqual(milk.energyKcal, 130)
        XCTAssertEqual(milk.sugarG, 11.8)    // 11.75
        let juice = NutrientMath.nutrients(for: BuiltInCatalog.drink(.juice), volumeML: 250)
        XCTAssertEqual(juice.energyKcal, 112.5)
        XCTAssertEqual(juice.sugarG, 22.5)
    }

    func testHydrationFactorAndClampsApplyFirst() {
        var drink = BuiltInCatalog.drink(.water)
        drink.hydrationFactor = 0.5
        XCTAssertEqual(NutrientMath.nutrients(for: drink, volumeML: 300).waterML, 150)
        drink.hydrationFactor = 0.01
        XCTAssertEqual(NutrientMath.nutrients(for: drink, volumeML: 300).waterML, 30)
        drink.hydrationFactor = 3
        XCTAssertEqual(NutrientMath.nutrients(for: drink, volumeML: 300).waterML, 300)
        XCTAssertEqual(NutrientMath.nutrients(for: BuiltInCatalog.drink(.water), volumeML: 1).waterML, 10)
        XCTAssertEqual(NutrientMath.nutrients(for: BuiltInCatalog.drink(.water), volumeML: 9000).waterML, 5000)
    }

    func testAmountOfComponent() {
        let n = Nutrients(waterML: 1, caffeineMG: 2, energyKcal: 3, sugarG: 4)
        XCTAssertEqual(HealthComponent.allCases.map { n.amount(of: $0) }, [1, 2, 3, 4])
        XCTAssertEqual(HealthComponent.allCases, [.water, .caffeine, .energy, .sugar])
    }

    func testSafeIntNeverTraps() {
        XCTAssertEqual(NutrientMath.safeInt(1234.5), 1235)
        XCTAssertEqual(NutrientMath.safeInt(.nan), 0)
        XCTAssertEqual(NutrientMath.safeInt(.infinity), 0)
        XCTAssertEqual(NutrientMath.safeInt(1e20), Int(Int32.max))
        XCTAssertEqual(NutrientMath.safeInt(-1e20), Int(Int32.min))
    }

    // MARK: - Built-in catalog (§5.1 table)

    func testBuiltInTable() {
        typealias Row = (BuiltInDrink, String, DrinkTint, Double, Double, Double, Int)
        let rows: [Row] = [
            (.water, "drop.fill", .blue, 0, 0, 0, 250),
            (.sparklingWater, "bubbles.and.sparkles.fill", .teal, 0, 0, 0, 330),
            (.colaZero, "takeoutbag.and.cup.and.straw.fill", .red, 9.6, 0.3, 0, 330),
            (.coffee, "cup.and.saucer.fill", .brown, 40, 1, 0, 200),
            (.tea, "mug.fill", .green, 20, 1, 0, 250),
            (.juice, "wineglass.fill", .orange, 0, 45, 9, 250),
            (.milk, "waterbottle.fill", .gray, 0, 52, 4.7, 250)
        ]
        XCTAssertEqual(rows.map { $0.0 }, BuiltInDrink.allCases)
        for (kind, symbol, tint, caffeine, kcal, sugar, volume) in rows {
            let drink = BuiltInCatalog.drink(kind)
            XCTAssertEqual(drink.id, kind.rawValue)
            XCTAssertEqual(drink.builtIn, kind)
            XCTAssertNil(drink.customName)
            XCTAssertEqual(drink.symbol, symbol, "\(kind)")
            XCTAssertEqual(drink.tint, tint, "\(kind)")
            XCTAssertEqual(drink.hydrationFactor, 1.0)
            XCTAssertEqual(drink.per100ML, NutrientsPer100ML(caffeineMG: caffeine, energyKcal: kcal, sugarG: sugar), "\(kind)")
            XCTAssertEqual(drink.defaultVolumeML, volume, "\(kind)")
            XCTAssertFalse(drink.isArchived)
            XCTAssertEqual(BuiltInCatalog.drink(id: kind.rawValue), drink)
        }
        XCTAssertEqual(BuiltInCatalog.allDrinks.map(\.id),
                       ["water", "sparklingWater", "colaZero", "coffee", "tea", "juice", "milk"])
        XCTAssertNil(BuiltInCatalog.drink(id: "kombucha"))
    }

    func testDefaultPresetsAndConstants() {
        XCTAssertEqual(BuiltInCatalog.defaultPresets, [
            Preset(id: "water-250", drinkID: "water", volumeML: 250),
            Preset(id: "water-500", drinkID: "water", volumeML: 500),
            Preset(id: "colaZero-330", drinkID: "colaZero", volumeML: 330),
            Preset(id: "coffee-200", drinkID: "coffee", volumeML: 200),
            Preset(id: "tea-250", drinkID: "tea", volumeML: 250)
        ])
        XCTAssertEqual(BuiltInCatalog.fallbackDrinkID, "water")
        XCTAssertEqual(BuiltInCatalog.fallbackPresetID, "water-250")
        XCTAssertEqual(BuiltInCatalog.customSymbols, [
            "drop.fill", "cup.and.saucer.fill", "mug.fill", "wineglass.fill", "waterbottle.fill",
            "takeoutbag.and.cup.and.straw.fill", "bubbles.and.sparkles.fill", "leaf.fill", "flame.fill",
            "bolt.fill", "birthday.cake.fill", "star.fill"
        ])
    }

    // MARK: - IntakeFactory

    func testIntakeFactoryMakesPendingSnapshot() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_758_800_000.123_456)
        let entry = IntakeFactory.make(drink: BuiltInCatalog.drink(.coffee), displayName: "Кофе", volumeML: 200,
                                       date: date, origin: .watch, source: .siri, id: id)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.drinkID, "coffee")
        XCTAssertEqual(entry.drinkName, "Кофе")
        XCTAssertEqual(entry.symbol, "cup.and.saucer.fill")
        XCTAssertEqual(entry.volumeML, 200)
        XCTAssertEqual(entry.nutrients.caffeineMG, 80)
        XCTAssertEqual(entry.origin, .watch)
        XCTAssertEqual(entry.source, .siri)
        XCTAssertEqual(entry.health, .pending)
        XCTAssertNil(entry.healthSavedAt)
        XCTAssertNil(entry.deletedAt)
        XCTAssertTrue(entry.isVisible)
        // Whole milliseconds.
        let ms = entry.date.timeIntervalSince1970 * 1000
        XCTAssertEqual(ms, ms.rounded(), accuracy: 0.001)
        XCTAssertEqual(entry.date.timeIntervalSince1970, 1_758_800_000.123, accuracy: 0.000_01)
    }

    func testIntakeFactoryClampsVolumeAndSurvivesJSON() throws {
        let entry = IntakeFactory.make(drink: BuiltInCatalog.drink(.water), displayName: "Water", volumeML: 99_999,
                                       date: Date(timeIntervalSince1970: 1_758_800_000.987_654), origin: .phone, source: .app)
        XCTAssertEqual(entry.volumeML, 5000)
        XCTAssertEqual(entry.nutrients.waterML, 5000)
        let data = try CoreJSON.encoder().encode(entry)
        let decoded = try CoreJSON.decoder().decode(IntakeEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testIntakeFactoryBlankNameFallsBackToDrinkName() {
        let entry = IntakeFactory.make(drink: BuiltInCatalog.drink(.tea), displayName: "  ", volumeML: 250,
                                       date: Date(), origin: .phone, source: .app)
        XCTAssertEqual(entry.drinkName, BuiltInCatalog.drink(.tea).name(AppLanguage.bundleDefault))
    }

    func testVisibility() {
        let now = Date()
        XCTAssertTrue(Fixtures.entry(date: now, health: .pending).isVisible)
        XCTAssertTrue(Fixtures.entry(date: now, health: .saved).isVisible)
        XCTAssertFalse(Fixtures.entry(date: now, health: .pendingDelete).isVisible)
        XCTAssertFalse(Fixtures.entry(date: now, health: .deleted).isVisible)
    }
}
