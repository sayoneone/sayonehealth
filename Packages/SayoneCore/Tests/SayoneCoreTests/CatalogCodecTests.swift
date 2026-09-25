import Foundation
import XCTest
@testable import SayoneCore

/// Catalog model, JSON codec and sanitize rules.
final class CatalogCodecTests: XCTestCase {
    private let updatedAt = Date(timeIntervalSince1970: 1_758_800_000)

    private func custom(_ id: String, name: String = "Custom", archived: Bool = false,
                        hydration: Double = 1, volume: Int = 250) -> Drink {
        Drink(id: id, builtIn: nil, customName: name, symbol: "star.fill", tint: .purple, hydrationFactor: hydration,
              per100ML: NutrientsPer100ML(caffeineMG: 1, energyKcal: 2, sugarG: 3), defaultVolumeML: volume, isArchived: archived)
    }

    func testRevisionRoundTripsExactly() throws {
        var catalog = Catalog.makeDefault(revision: 1_758_800_000_123, now: updatedAt)
        let data = try CoreJSON.encoder().encode(catalog)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"revision\":1758800000123"), text)
        let decoded = try CoreJSON.decoder().decode(Catalog.self, from: data)
        XCTAssertEqual(decoded.revision, 1_758_800_000_123)
        XCTAssertEqual(decoded, catalog)

        catalog.revision = Int64.max - 1
        let big = try CoreJSON.decoder().decode(Catalog.self, from: CoreJSON.encoder().encode(catalog))
        XCTAssertEqual(big.revision, Int64.max - 1)
    }

    func testEncoderUsesSortedKeysAndMilliseconds() throws {
        let snapshot = HealthSnapshot(dayStart: Date(timeIntervalSince1970: 1_758_747_600), externalWaterML: 1.5,
                                      otherDeviceWaterML: 0.5, readAt: Date(timeIntervalSince1970: 1_758_800_000.25))
        let data = try CoreJSON.encoder().encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        // Keys are sorted.
        let keys = ["dayStart", "externalWaterML", "otherDeviceWaterML", "readAt"]
        let positions = keys.compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        XCTAssertEqual(positions.count, keys.count, text)
        XCTAssertEqual(positions, positions.sorted(), text)
        // Dates are milliseconds since 1970.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["dayStart"] as? NSNumber)?.doubleValue, 1_758_747_600_000)
        XCTAssertEqual((object["readAt"] as? NSNumber)?.doubleValue, 1_758_800_000_250)
        XCTAssertEqual((object["externalWaterML"] as? NSNumber)?.doubleValue, 1.5)
        let decoded = try CoreJSON.decoder().decode(HealthSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testDecodesHandWrittenCatalogWithUnknownKeysAndTint() throws {
        let json = """
        {"version":1,"revision":42,"updatedAt":1758800000000,"futureField":"ignored",
         "drinks":[{"id":"custom-1","customName":"Kvass","symbol":"leaf.fill","tint":"magenta",
                    "hydrationFactor":0.9,"per100ML":{"caffeineMG":0,"energyKcal":27,"sugarG":5},
                    "defaultVolumeML":330,"isArchived":false}],
         "presets":[{"id":"preset-1","drinkID":"custom-1","volumeML":500}],
         "settings":{"dailyGoalML":2200,"writeNutrients":false}}
        """
        let catalog = try CoreJSON.decoder().decode(Catalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.revision, 42)
        XCTAssertEqual(catalog.drinks.first?.tint, .blue)
        XCTAssertNil(catalog.drinks.first?.builtIn)
        XCTAssertEqual(catalog.settings, UserSettings(dailyGoalML: 2200, writeNutrients: false))
        let clean = catalog.sanitized()
        XCTAssertEqual(clean.drinks.map(\.id), ["custom-1"] + BuiltInDrink.allCases.map(\.rawValue))
        XCTAssertEqual(clean.presets, [Preset(id: "preset-1", drinkID: "custom-1", volumeML: 500)])
    }

    func testMakeDefault() {
        let c = Catalog.makeDefault(revision: 7, now: updatedAt)
        XCTAssertEqual(c.version, 1)
        XCTAssertEqual(Catalog.currentVersion, 1)
        XCTAssertEqual(Catalog.maxPresets, 12)
        XCTAssertEqual(c.revision, 7)
        XCTAssertEqual(c.updatedAt, updatedAt)
        XCTAssertEqual(c.drinks, BuiltInCatalog.allDrinks)
        XCTAssertEqual(c.presets, BuiltInCatalog.defaultPresets)
        XCTAssertEqual(c.settings, UserSettings())
        XCTAssertEqual(c.settings.dailyGoalML, 2000)
        XCTAssertTrue(c.settings.writeNutrients)
        XCTAssertEqual(UserSettings.goalRange, 500...6000)
        XCTAssertEqual(Catalog.makeDefault().revision, 0)
        XCTAssertEqual(c, c.sanitized())
    }

    func testLookupsAndPresetDisplays() {
        var c = Catalog.makeDefault(now: updatedAt)
        c.drinks.append(custom("custom-a", name: "Mors", archived: true))
        c.presets.insert(Preset(id: "p-missing", drinkID: "custom-missing", volumeML: 100), at: 0)
        XCTAssertEqual(c.drink(id: "custom-a")?.isArchived, true)
        XCTAssertNil(c.drink(id: "custom-missing"))
        XCTAssertEqual(c.activeDrinks.map(\.id), BuiltInDrink.allCases.map(\.rawValue))
        XCTAssertEqual(c.resolvedPresets().map(\.id), BuiltInCatalog.defaultPresets.map(\.id))
        XCTAssertEqual(c.resolvedPresets().first?.drink, BuiltInCatalog.drink(.water))

        let ru = c.presetDisplays(.ru)
        XCTAssertEqual(ru.map(\.drinkName), ["Вода", "Вода", "Кола без сахара", "Кофе", "Чай"])
        XCTAssertEqual(ru[2], PresetDisplay(id: "colaZero-330", drinkID: "colaZero", drinkName: "Кола без сахара",
                                            symbol: "takeoutbag.and.cup.and.straw.fill", tint: .red, volumeML: 330))
        XCTAssertEqual(ru[0].localizedTitle(.ru), "Вода · 250\(Fixtures.nbsp)мл")
        XCTAssertEqual(c.presetDisplays(.en)[1].localizedTitle(.en), "Water · 500\(Fixtures.nbsp)ml")
    }

    func testPresetDisplayFallbackAndCodable() throws {
        let fallback = PresetDisplay.builtInFallback(.ru)
        XCTAssertEqual(fallback, PresetDisplay(id: "water-250", drinkID: "water", drinkName: "Вода", symbol: "drop.fill",
                                               tint: .blue, volumeML: 250))
        XCTAssertEqual(PresetDisplay.builtInFallback(.en).drinkName, "Water")
        XCTAssertEqual(PresetDisplay.builtInFallback(.en).localizedTitle(.en), "Water · 250\(Fixtures.nbsp)ml")
        let decoded = try CoreJSON.decoder().decode(PresetDisplay.self, from: CoreJSON.encoder().encode(fallback))
        XCTAssertEqual(decoded, fallback)
        let resolved = ResolvedPreset(preset: Preset(id: "p", drinkID: "tea", volumeML: 300), drink: BuiltInCatalog.drink(.tea))
        XCTAssertEqual(resolved.id, "p")
        XCTAssertEqual(PresetDisplay(resolved, lang: .en).localizedTitle(.ru), "Tea · 300\(Fixtures.nbsp)мл")
    }

    // MARK: - sanitized()

    func testSanitizeDropsDuplicateDrinksKeepingFirst() {
        var c = Catalog.makeDefault(now: updatedAt)
        var otherWater = BuiltInCatalog.drink(.water)
        otherWater.symbol = "star.fill"
        c.drinks.append(otherWater)
        c.drinks.append(custom("custom-a", name: "First"))
        c.drinks.append(custom("custom-a", name: "Second"))
        let s = c.sanitized()
        XCTAssertEqual(s.drinks.filter { $0.id == "water" }.map(\.symbol), ["drop.fill"])
        XCTAssertEqual(s.drinks.filter { $0.id == "custom-a" }.map(\.customName), ["First"])
    }

    func testSanitizeAppendsMissingBuiltInsInOrder() {
        let c = Catalog(version: 0, revision: 3, updatedAt: updatedAt,
                        drinks: [custom("custom-a"), BuiltInCatalog.drink(.tea)],
                        presets: [], settings: UserSettings())
        XCTAssertEqual(c.sanitized().drinks.map(\.id),
                       ["custom-a", "tea", "water", "sparklingWater", "colaZero", "coffee", "juice", "milk"])
    }

    func testSanitizeClamps() {
        var c = Catalog.makeDefault(now: updatedAt)
        c.drinks.append(custom("custom-a", hydration: 7, volume: 0))
        c.drinks.append(custom("custom-b", hydration: 0.01, volume: 99_999))
        c.presets.append(Preset(id: "p1", drinkID: "custom-a", volumeML: 1))
        c.presets.append(Preset(id: "p2", drinkID: "custom-b", volumeML: 100_000))
        c.settings.dailyGoalML = 10
        var s = c.sanitized()
        XCTAssertEqual(s.drink(id: "custom-a")?.hydrationFactor, 1.0)
        XCTAssertEqual(s.drink(id: "custom-a")?.defaultVolumeML, 10)
        XCTAssertEqual(s.drink(id: "custom-b")?.hydrationFactor, 0.1)
        XCTAssertEqual(s.drink(id: "custom-b")?.defaultVolumeML, 5000)
        XCTAssertEqual(s.presets.suffix(2).map(\.volumeML), [10, 5000])
        XCTAssertEqual(s.settings.dailyGoalML, 500)
        c.settings.dailyGoalML = 60_000
        s = c.sanitized()
        XCTAssertEqual(s.settings.dailyGoalML, 6000)
    }

    func testSanitizeDropsBadPresets() {
        var c = Catalog.makeDefault(now: updatedAt)
        c.drinks.append(custom("custom-archived", archived: true))
        c.presets = [
            Preset(id: "a", drinkID: "water", volumeML: 250),
            Preset(id: "a", drinkID: "tea", volumeML: 250),               // duplicate id
            Preset(id: "b", drinkID: "custom-missing", volumeML: 250),    // unknown drink
            Preset(id: "c", drinkID: "custom-archived", volumeML: 250),   // archived drink
            Preset(id: "d", drinkID: "milk", volumeML: 250)
        ]
        XCTAssertEqual(c.sanitized().presets.map(\.id), ["a", "d"])
        XCTAssertEqual(c.sanitized().presets.first?.drinkID, "water")
    }

    func testSanitizeTruncatesToMaxPresetsAndSetsVersion() {
        var c = Catalog.makeDefault(now: updatedAt)
        c.version = 99
        c.presets = (0..<20).map { Preset(id: "p\($0)", drinkID: "water", volumeML: 100 + $0) }
        let s = c.sanitized()
        XCTAssertEqual(s.presets.count, 12)
        XCTAssertEqual(s.presets.first?.id, "p0")
        XCTAssertEqual(s.presets.last?.id, "p11")
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.revision, c.revision, "sanitize never touches the revision")
        XCTAssertEqual(s, s.sanitized(), "idempotent")
    }

    func testIntakeEntryRoundTrip() throws {
        var entry = IntakeFactory.make(drink: BuiltInCatalog.drink(.juice), displayName: "Сок", volumeML: 250,
                                       date: Date(timeIntervalSince1970: 1_758_800_000.456_789), origin: .watch, source: .widget)
        entry.health = .saved
        entry.healthSavedAt = Date(timeIntervalSince1970: 1_758_800_001)
        let decoded = try CoreJSON.decoder().decode(IntakeEntry.self, from: CoreJSON.encoder().encode(entry))
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(decoded.nutrients.energyKcal, 112.5)
    }
}
