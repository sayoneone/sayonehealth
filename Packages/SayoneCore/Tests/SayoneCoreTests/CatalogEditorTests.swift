import Foundation
import XCTest
@testable import SayoneCore

final class CatalogEditorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_758_800_000)
    private var nowMS: Int64 { 1_758_800_000_000 }

    private func base(revision: Int64 = 5) -> Catalog {
        Catalog.makeDefault(revision: revision, now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func assertBumped(_ c: Catalog, from old: Int64, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(c.revision, max(old + 1, nowMS), file: file, line: line)
        XCTAssertEqual(c.updatedAt, now, file: file, line: line)
    }

    func testNextRevision() {
        XCTAssertEqual(Catalog.nextRevision(after: 0, now: now), nowMS)
        XCTAssertEqual(Catalog.nextRevision(after: nowMS, now: now), nowMS + 1)
        XCTAssertEqual(Catalog.nextRevision(after: nowMS + 500, now: now), nowMS + 501)
        XCTAssertEqual(Catalog.nextRevision(after: Int64.max, now: now), Int64.max)
        XCTAssertEqual(Catalog.nextRevision(after: 0, now: Date(timeIntervalSince1970: 1_758_800_000.1239)),
                       1_758_800_000_123)
    }

    func testAddCustomDrink() {
        var c = base()
        let drink = CatalogEditor.addCustomDrink(to: &c, name: "  Квас ", symbol: "leaf.fill", tint: .brown,
                                                 hydrationFactor: 5, per100ML: NutrientsPer100ML(energyKcal: 27),
                                                 defaultVolumeML: 1, now: now)
        XCTAssertTrue(drink.id.hasPrefix("custom-"))
        XCTAssertNotNil(UUID(uuidString: String(drink.id.dropFirst("custom-".count))))
        XCTAssertNil(drink.builtIn)
        XCTAssertEqual(drink.customName, "Квас")
        XCTAssertEqual(drink.hydrationFactor, 1.0)
        XCTAssertEqual(drink.defaultVolumeML, 10)
        XCTAssertFalse(drink.isArchived)
        XCTAssertEqual(c.drinks.last, drink)
        XCTAssertEqual(c.drinks.count, BuiltInDrink.allCases.count + 1)
        assertBumped(c, from: 5)
    }

    func testUpdateCustomDrink() {
        var c = base()
        var drink = CatalogEditor.addCustomDrink(to: &c, name: "Kvass", symbol: "leaf.fill", tint: .brown,
                                                 hydrationFactor: 0.9, per100ML: NutrientsPer100ML(), defaultVolumeML: 330, now: now)
        let revision = c.revision
        drink.customName = "Mors"
        drink.tint = .red
        drink.hydrationFactor = 0
        CatalogEditor.updateDrink(in: &c, drink, now: now.addingTimeInterval(10))
        let stored = c.drink(id: drink.id)
        XCTAssertEqual(stored?.customName, "Mors")
        XCTAssertEqual(stored?.tint, .red)
        XCTAssertEqual(stored?.hydrationFactor, 0.1)
        XCTAssertEqual(c.revision, max(revision + 1, nowMS + 10_000))
    }

    func testUpdateBuiltInIgnoresNameFields() {
        var c = base()
        var water = BuiltInCatalog.drink(.water)
        water.customName = "Renamed"
        water.builtIn = nil
        water.isArchived = true
        water.hydrationFactor = 0.8
        water.defaultVolumeML = 300
        CatalogEditor.updateDrink(in: &c, water, now: now)
        let stored = c.drink(id: "water")
        XCTAssertNil(stored?.customName)
        XCTAssertEqual(stored?.builtIn, .water)
        XCTAssertEqual(stored?.isArchived, false)
        XCTAssertEqual(stored?.hydrationFactor, 0.8)
        XCTAssertEqual(stored?.defaultVolumeML, 300)
        XCTAssertEqual(stored?.name(.ru), "Вода")
        assertBumped(c, from: 5)
    }

    func testUpdateUnknownDrinkIsNoOp() {
        var c = base()
        let before = c
        CatalogEditor.updateDrink(in: &c, Drink.unknown(id: "custom-missing", name: "X"), now: now)
        XCTAssertEqual(c, before)
    }

    func testArchiveCustomDrinkRemovesItsPresets() {
        var c = base()
        let drink = CatalogEditor.addCustomDrink(to: &c, name: "Kvass", symbol: "leaf.fill", tint: .brown,
                                                 hydrationFactor: 1, per100ML: NutrientsPer100ML(), defaultVolumeML: 330, now: now)
        let preset = CatalogEditor.addPreset(to: &c, drinkID: drink.id, volumeML: 500, now: now)
        XCTAssertNotNil(preset)
        let revision = c.revision
        CatalogEditor.archiveDrink(in: &c, id: drink.id, now: now)
        XCTAssertEqual(c.drink(id: drink.id)?.isArchived, true)
        XCTAssertFalse(c.presets.contains { $0.drinkID == drink.id })
        XCTAssertFalse(c.activeDrinks.contains { $0.id == drink.id })
        XCTAssertEqual(c.revision, revision + 1)
    }

    func testBuiltInsCannotBeArchived() {
        var c = base()
        let before = c
        CatalogEditor.archiveDrink(in: &c, id: "water", now: now)
        CatalogEditor.archiveDrink(in: &c, id: "nope", now: now)
        XCTAssertEqual(c, before)
    }

    func testAddPreset() {
        var c = base()
        let p = CatalogEditor.addPreset(to: &c, drinkID: "juice", volumeML: 9000, now: now)
        XCTAssertEqual(p?.drinkID, "juice")
        XCTAssertEqual(p?.volumeML, 5000)
        XCTAssertEqual(p?.id.hasPrefix("preset-"), true)
        XCTAssertEqual(c.presets.last, p)
        assertBumped(c, from: 5)

        let before = c
        XCTAssertNil(CatalogEditor.addPreset(to: &c, drinkID: "custom-unknown", volumeML: 250, now: now))
        XCTAssertEqual(c, before)
    }

    func testAddPresetStopsAtMax() {
        var c = base()
        while c.presets.count < Catalog.maxPresets {
            XCTAssertNotNil(CatalogEditor.addPreset(to: &c, drinkID: "water", volumeML: 100 + c.presets.count, now: now))
        }
        XCTAssertEqual(c.presets.count, 12)
        let before = c
        XCTAssertNil(CatalogEditor.addPreset(to: &c, drinkID: "water", volumeML: 250, now: now))
        XCTAssertEqual(c, before)
    }

    func testUpdateAndRemovePreset() {
        var c = base()
        CatalogEditor.updatePreset(in: &c, Preset(id: "water-500", drinkID: "tea", volumeML: 400), now: now)
        XCTAssertEqual(c.presets[1], Preset(id: "water-500", drinkID: "tea", volumeML: 400))
        assertBumped(c, from: 5)

        let revision = c.revision
        CatalogEditor.removePreset(from: &c, id: "coffee-200", now: now)
        XCTAssertEqual(c.presets.map(\.id), ["water-250", "water-500", "colaZero-330", "tea-250"])
        XCTAssertEqual(c.revision, revision + 1)

        let before = c
        CatalogEditor.removePreset(from: &c, id: "missing", now: now)
        CatalogEditor.updatePreset(in: &c, Preset(id: "missing", drinkID: "tea", volumeML: 400), now: now)
        CatalogEditor.updatePreset(in: &c, Preset(id: "water-250", drinkID: "custom-unknown", volumeML: 400), now: now)
        XCTAssertEqual(c, before)
    }

    func testMovePresetsUsesOnMoveSemantics() {
        func moved(_ source: [Int], _ destination: Int) -> [String] {
            var c = base()
            CatalogEditor.movePresets(in: &c, from: IndexSet(source), to: destination, now: now)
            return c.presets.map { String($0.id.prefix { $0 != "-" }) + String($0.volumeML) }
        }
        // Default: water250, water500, colaZero330, coffee200, tea250
        XCTAssertEqual(moved([0], 2), ["water500", "water250", "colaZero330", "coffee200", "tea250"])
        XCTAssertEqual(moved([0], 5), ["water500", "colaZero330", "coffee200", "tea250", "water250"])
        XCTAssertEqual(moved([4], 0), ["tea250", "water250", "water500", "colaZero330", "coffee200"])
        XCTAssertEqual(moved([1, 3], 5), ["water250", "colaZero330", "tea250", "water500", "coffee200"])
        XCTAssertEqual(moved([1, 3], 0), ["water500", "coffee200", "water250", "colaZero330", "tea250"])
        XCTAssertEqual(moved([3], 1), ["water250", "coffee200", "water500", "colaZero330", "tea250"])

        var c = base()
        CatalogEditor.movePresets(in: &c, from: IndexSet([2]), to: 0, now: now)
        assertBumped(c, from: 5)

        // No-op moves do not bump the revision.
        for (source, destination) in [([0], 0), ([0], 1), ([4], 5), ([9], 0)] {
            var unchanged = base()
            let before = unchanged
            CatalogEditor.movePresets(in: &unchanged, from: IndexSet(source), to: destination, now: now)
            XCTAssertEqual(unchanged, before, "\(source) → \(destination)")
        }
    }

    func testSettingsSetters() {
        var c = base()
        CatalogEditor.setDailyGoal(in: &c, ml: 2500, now: now)
        XCTAssertEqual(c.settings.dailyGoalML, 2500)
        assertBumped(c, from: 5)
        CatalogEditor.setDailyGoal(in: &c, ml: 100, now: now)
        XCTAssertEqual(c.settings.dailyGoalML, 500)
        CatalogEditor.setDailyGoal(in: &c, ml: 100_000, now: now)
        XCTAssertEqual(c.settings.dailyGoalML, 6000)

        let revision = c.revision
        CatalogEditor.setWriteNutrients(in: &c, false, now: now)
        XCTAssertFalse(c.settings.writeNutrients)
        XCTAssertEqual(c.revision, revision + 1)
    }

    func testEveryMutationIncreasesRevisionEvenWithFutureRevision() {
        var c = base(revision: nowMS + 1_000_000)
        let start = c.revision
        let drink = CatalogEditor.addCustomDrink(to: &c, name: "A", symbol: "star.fill", tint: .purple,
                                                 hydrationFactor: 1, per100ML: NutrientsPer100ML(), defaultVolumeML: 200, now: now)
        CatalogEditor.updateDrink(in: &c, drink, now: now)
        _ = CatalogEditor.addPreset(to: &c, drinkID: drink.id, volumeML: 200, now: now)
        CatalogEditor.updatePreset(in: &c, Preset(id: "water-250", drinkID: "water", volumeML: 300), now: now)
        CatalogEditor.movePresets(in: &c, from: IndexSet([0]), to: 2, now: now)
        CatalogEditor.removePreset(from: &c, id: "tea-250", now: now)
        CatalogEditor.archiveDrink(in: &c, id: drink.id, now: now)
        CatalogEditor.setDailyGoal(in: &c, ml: 3000, now: now)
        CatalogEditor.setWriteNutrients(in: &c, false, now: now)
        XCTAssertEqual(c.revision, start + 9)
        XCTAssertEqual(c, c.sanitized())
    }
}
