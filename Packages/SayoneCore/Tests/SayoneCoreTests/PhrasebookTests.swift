import Foundation
import XCTest
@testable import SayoneCore

/// Exact texts from §6.4. `{vol}` = VolumeFormat.short, `{progress}` = VolumeFormat.progress.
final class PhrasebookTests: XCTestCase {
    private let n = Fixtures.nbsp
    private let summary = TodaySummary(waterML: 1200, goalML: 2000, localWaterML: 1200, externalWaterML: 0,
                                       otherDeviceWaterML: 0, pendingCount: 0, lastLocal: nil,
                                       undoAvailableUntil: nil, healthReadAt: nil)

    func testDrinkNames() {
        let ru = BuiltInDrink.allCases.map { Phrasebook.drinkName($0, .ru) }
        XCTAssertEqual(ru, ["Вода", "Газированная вода", "Кола без сахара", "Кофе", "Чай", "Сок", "Молоко"])
        let en = BuiltInDrink.allCases.map { Phrasebook.drinkName($0, .en) }
        XCTAssertEqual(en, ["Water", "Sparkling Water", "Cola Zero", "Coffee", "Tea", "Juice", "Milk"])
    }

    func testAccusatives() {
        let ru = BuiltInDrink.allCases.map { Phrasebook.drinkAccusative($0, .ru) }
        XCTAssertEqual(ru, ["воду", "газированную воду", "колу без сахара", "кофе", "чай", "сок", "молоко"])
        let en = BuiltInDrink.allCases.map { Phrasebook.drinkAccusative($0, .en) }
        XCTAssertEqual(en, ["water", "sparkling water", "cola zero", "coffee", "tea", "juice", "milk"])
    }

    func testGenericDrink() {
        XCTAssertEqual(Phrasebook.genericDrink(.ru), "Напиток")
        XCTAssertEqual(Phrasebook.genericDrink(.en), "Drink")
    }

    func testLoggedSaved() {
        XCTAssertEqual(Phrasebook.logged(drinkName: "Вода", volumeML: 250, summary: summary, savedToHealth: true,
                                         healthAuthorized: true, .ru),
                       "Записано: Вода, 250\(n)мл. Сегодня 1,2 из 2\(n)л.")
        XCTAssertEqual(Phrasebook.logged(drinkName: "Water", volumeML: 250, summary: summary, savedToHealth: true,
                                         healthAuthorized: true, .en),
                       "Logged Water, 250\(n)ml. Today: 1.2 of 2\(n)L.")
        // savedToHealth wins even if the auth flag is stale.
        XCTAssertEqual(Phrasebook.logged(drinkName: "Water", volumeML: 250, summary: summary, savedToHealth: true,
                                         healthAuthorized: false, .en),
                       "Logged Water, 250\(n)ml. Today: 1.2 of 2\(n)L.")
    }

    func testLoggedNotSavedNotAuthorized() {
        XCTAssertEqual(Phrasebook.logged(drinkName: "Кола без сахара", volumeML: 330, summary: summary, savedToHealth: false,
                                         healthAuthorized: false, .ru),
                       "Записано: Кола без сахара, 330\(n)мл. Сегодня 1,2 из 2\(n)л. Откройте SayoneHealth, чтобы разрешить доступ к «Здоровью».")
        XCTAssertEqual(Phrasebook.logged(drinkName: "Cola Zero", volumeML: 330, summary: summary, savedToHealth: false,
                                         healthAuthorized: false, .en),
                       "Logged Cola Zero, 330\(n)ml. Today: 1.2 of 2\(n)L. Open SayoneHealth to allow access to Health.")
    }

    func testLoggedNotSavedAuthorized() {
        XCTAssertEqual(Phrasebook.logged(drinkName: "Кофе", volumeML: 1500, summary: summary, savedToHealth: false,
                                         healthAuthorized: true, .ru),
                       "Записано: Кофе, 1,5\(n)л. Сегодня 1,2 из 2\(n)л. В «Здоровье» запишется позже.")
        XCTAssertEqual(Phrasebook.logged(drinkName: "Coffee", volumeML: 1500, summary: summary, savedToHealth: false,
                                         healthAuthorized: true, .en),
                       "Logged Coffee, 1.5\(n)L. Today: 1.2 of 2\(n)L. It will be saved to Health later.")
    }

    func testFixedTexts() {
        XCTAssertEqual(Phrasebook.duplicateIgnored(.ru), "Уже записано.")
        XCTAssertEqual(Phrasebook.duplicateIgnored(.en), "Already logged.")
        XCTAssertEqual(Phrasebook.storeFailed(.ru), "Не удалось записать. Разблокируйте устройство и повторите.")
        XCTAssertEqual(Phrasebook.storeFailed(.en), "Couldn't log the drink. Unlock the device and try again.")
        XCTAssertEqual(Phrasebook.nothingToUndo(.ru), "Нечего отменять.")
        XCTAssertEqual(Phrasebook.nothingToUndo(.en), "Nothing to undo.")
        XCTAssertEqual(Phrasebook.notDeletableHere(.ru),
                       "Эту запись нужно удалить на устройстве, где она сделана, или в приложении «Здоровье».")
        XCTAssertEqual(Phrasebook.notDeletableHere(.en),
                       "Delete this entry on the device where it was logged, or in the Health app.")
        XCTAssertEqual(Phrasebook.healthAccessMissing(.ru), "Откройте SayoneHealth, чтобы разрешить доступ к «Здоровью».")
        XCTAssertEqual(Phrasebook.healthAccessMissing(.en), "Open SayoneHealth to allow access to Health.")
    }

    func testToday() {
        XCTAssertEqual(Phrasebook.today(summary, .ru), "Сегодня выпито 1,2 из 2\(n)л.")
        XCTAssertEqual(Phrasebook.today(summary, .en), "Today you've had 1.2 of 2\(n)L.")
    }

    func testUndone() {
        XCTAssertEqual(Phrasebook.undone(drinkName: "Чай", volumeML: 250, .ru), "Отменено: Чай, 250\(n)мл.")
        XCTAssertEqual(Phrasebook.undone(drinkName: "Tea", volumeML: 250, .en), "Undone: Tea, 250\(n)ml.")
    }

    func testUndoQueued() {
        XCTAssertEqual(Phrasebook.undoQueued(drinkName: "Сок", volumeML: 200, .ru),
                       "Отменено: Сок, 200\(n)мл. Из «Здоровья» удалится позже.")
        XCTAssertEqual(Phrasebook.undoQueued(drinkName: "Juice", volumeML: 200, .en),
                       "Undone: Juice, 200\(n)ml. It will be removed from Health later.")
    }

    func testToast() {
        XCTAssertEqual(Phrasebook.toast(drinkName: "Вода", volumeML: 500, .ru), "Записано · Вода, 500\(n)мл")
        XCTAssertEqual(Phrasebook.toast(drinkName: "Water", volumeML: 500, .en), "Logged · Water, 500\(n)ml")
        XCTAssertTrue(Phrasebook.toast(drinkName: "Water", volumeML: 500, .en).unicodeScalars.contains("\u{00B7}"))
    }

    func testTypographicCharacters() {
        // Guillemets «» (U+00AB/U+00BB), ASCII apostrophes.
        XCTAssertTrue(Phrasebook.healthAccessMissing(.ru).unicodeScalars.contains("\u{00AB}"))
        XCTAssertTrue(Phrasebook.healthAccessMissing(.ru).unicodeScalars.contains("\u{00BB}"))
        XCTAssertTrue(Phrasebook.storeFailed(.en).contains("Couldn't"))
    }
}
