import Foundation

public enum IntakeFactory {
    /// Clamps volume, rounds date to whole ms, computes nutrients, health = .pending.
    public static func make(drink: Drink, displayName: String, volumeML: Int, date: Date,
                            origin: DeviceKind, source: LogSource, id: UUID = UUID()) -> IntakeEntry {
        let volume = NutrientMath.clampVolume(volumeML)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? drink.name(AppLanguage.bundleDefault) : displayName
        return IntakeEntry(id: id,
                           date: wholeMilliseconds(date),
                           drinkID: drink.id,
                           drinkName: name,
                           symbol: drink.symbol,
                           volumeML: volume,
                           nutrients: NutrientMath.nutrients(for: drink, volumeML: volume),
                           origin: origin,
                           source: source,
                           health: .pending,
                           healthSavedAt: nil,
                           deletedAt: nil)
    }

    /// The date rounded to whole milliseconds since 1970, so it survives the JSON round trip.
    static func wholeMilliseconds(_ date: Date) -> Date {
        let ms = (date.timeIntervalSince1970 * 1000).rounded()
        guard ms.isFinite else { return date }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
