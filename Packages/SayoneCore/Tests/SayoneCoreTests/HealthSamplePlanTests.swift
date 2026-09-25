import Foundation
import XCTest
@testable import SayoneCore

final class HealthSamplePlanTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_758_800_000.5)

    private func entry(_ kind: BuiltInDrink, _ ml: Int, id: UUID = UUID(), origin: DeviceKind = .phone) -> IntakeEntry {
        IntakeFactory.make(drink: BuiltInCatalog.drink(kind), displayName: Phrasebook.drinkName(kind, .ru),
                           volumeML: ml, date: date, origin: origin, source: .app, id: id)
    }

    private func entry(nutrients: Nutrients) -> IntakeEntry {
        IntakeEntry(id: UUID(), date: date, drinkID: "custom-x", drinkName: "X", symbol: "star.fill", volumeML: 100,
                    nutrients: nutrients, origin: .watch, source: .widget)
    }

    func testMetadataConstants() {
        XCTAssertEqual(HealthMetadata.entryIDKey, "SayoneEntryID")
        XCTAssertEqual(HealthMetadata.drinkIDKey, "SayoneDrinkID")
        XCTAssertEqual(HealthMetadata.volumeKey, "SayoneVolumeML")
        XCTAssertEqual(HealthMetadata.originKey, "SayoneOrigin")
        XCTAssertEqual(HealthMetadata.syncVersion, 1)
        let id = UUID(uuidString: "8C1E0D4A-1111-2222-3333-44445555669A")!
        XCTAssertEqual(HealthMetadata.syncIdentifier(entryID: id, component: .water), "8C1E0D4A-1111-2222-3333-44445555669A.water")
        XCTAssertEqual(HealthMetadata.syncIdentifier(entryID: id, component: .caffeine), "8C1E0D4A-1111-2222-3333-44445555669A.caffeine")
    }

    func testMinimumAmounts() {
        XCTAssertEqual(HealthMetadata.minimumAmount(.water), 1)
        XCTAssertEqual(HealthMetadata.minimumAmount(.caffeine), 0.5)
        XCTAssertEqual(HealthMetadata.minimumAmount(.energy), 0.5)
        XCTAssertEqual(HealthMetadata.minimumAmount(.sugar), 0.1)
    }

    func testComponents() {
        XCTAssertEqual(HealthSamplePlan.components(for: entry(.water, 250), includeNutrients: true), [.water])
        XCTAssertEqual(HealthSamplePlan.components(for: entry(.coffee, 200), includeNutrients: true), [.water, .caffeine, .energy])
        XCTAssertEqual(HealthSamplePlan.components(for: entry(.coffee, 200), includeNutrients: false), [.water])
        XCTAssertEqual(HealthSamplePlan.components(for: entry(.juice, 250), includeNutrients: true), [.water, .energy, .sugar])
        XCTAssertEqual(HealthSamplePlan.components(for: entry(.milk, 250), includeNutrients: true), [.water, .energy, .sugar])
        // Cola Zero 330: caffeine 31.7, energy 1.0 (0.99 rounded), sugar 0.
        XCTAssertEqual(HealthSamplePlan.components(for: entry(.colaZero, 330), includeNutrients: true), [.water, .caffeine, .energy])
        // Cola Zero 100: energy 0.3 < 0.5 → dropped.
        XCTAssertEqual(HealthSamplePlan.components(for: entry(.colaZero, 100), includeNutrients: true), [.water, .caffeine])
    }

    func testMinimumThresholdsAreInclusive() {
        let atMinimum = entry(nutrients: Nutrients(waterML: 1, caffeineMG: 0.5, energyKcal: 0.5, sugarG: 0.1))
        XCTAssertEqual(HealthSamplePlan.components(for: atMinimum, includeNutrients: true), [.water, .caffeine, .energy, .sugar])
        let below = entry(nutrients: Nutrients(waterML: 0.9, caffeineMG: 0.4, energyKcal: 0.4, sugarG: 0.05))
        XCTAssertEqual(HealthSamplePlan.components(for: below, includeNutrients: true), [])
        XCTAssertEqual(HealthSamplePlan.specs(for: below, includeNutrients: true), [])
    }

    func testSpecs() {
        let id = UUID()
        let e = entry(.coffee, 200, id: id, origin: .watch)
        let specs = HealthSamplePlan.specs(for: e, includeNutrients: true)
        XCTAssertEqual(specs.map(\.component), [.water, .caffeine, .energy])
        XCTAssertEqual(specs.map(\.amount), [200, 80, 2])
        let custom: [String: MetadataValue] = [
            "SayoneEntryID": .string(id.uuidString),
            "SayoneDrinkID": .string("coffee"),
            "SayoneVolumeML": .number(200),
            "SayoneOrigin": .string("watch")
        ]
        XCTAssertEqual(specs[0], HealthSampleSpec(component: .water, amount: 200, date: e.date,
                                                  syncIdentifier: "\(id.uuidString).water", syncVersion: 1,
                                                  foodType: "Кофе", custom: custom))
        for spec in specs {
            XCTAssertEqual(spec.date, e.date)
            XCTAssertEqual(spec.syncIdentifier, "\(id.uuidString).\(spec.component.rawValue)")
            XCTAssertEqual(spec.syncVersion, 1)
            XCTAssertEqual(spec.foodType, "Кофе")
            XCTAssertEqual(spec.custom, custom)
        }
        XCTAssertEqual(HealthSamplePlan.specs(for: e, includeNutrients: false).map(\.component), [.water])
    }

    func testWaterAlwaysPresentForAnyClampedEntry() {
        var drink = BuiltInCatalog.drink(.water)
        drink.hydrationFactor = 0   // clamps to 0.1
        let e = IntakeFactory.make(drink: drink, displayName: "W", volumeML: 0, date: date, origin: .phone, source: .app)
        XCTAssertEqual(e.nutrients.waterML, 1)
        XCTAssertEqual(HealthSamplePlan.components(for: e, includeNutrients: false), [.water])
    }
}
