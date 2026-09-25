import Foundation

/// Every catalog mutation. Each applied change sets revision = Catalog.nextRevision(after:now:), updatedAt = now,
/// then sanitizes. A change that finds nothing to act on (unknown id, full preset list …) leaves the catalog untouched.
public enum CatalogEditor {
    @discardableResult
    public static func addCustomDrink(to c: inout Catalog, name: String, symbol: String, tint: DrinkTint,
                                      hydrationFactor: Double, per100ML: NutrientsPer100ML, defaultVolumeML: Int,
                                      now: Date = Date()) -> Drink {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let drink = Drink(id: "custom-\(UUID().uuidString)",
                          builtIn: nil,
                          customName: trimmed.isEmpty ? nil : trimmed,
                          symbol: symbol,
                          tint: tint,
                          hydrationFactor: NutrientMath.clampHydration(hydrationFactor),
                          per100ML: per100ML,
                          defaultVolumeML: NutrientMath.clampVolume(defaultVolumeML),
                          isArchived: false)
        c.drinks.append(drink)
        commit(&c, now: now)
        return c.drink(id: drink.id) ?? drink
    }

    /// Replaces the drink with the same id. For built-ins the name fields (`builtIn`, `customName`) are ignored
    /// and `isArchived` is forced to false (built-ins cannot be archived).
    public static func updateDrink(in c: inout Catalog, _ drink: Drink, now: Date = Date()) {
        guard let index = c.drinks.firstIndex(where: { $0.id == drink.id }) else { return }
        let old = c.drinks[index]
        var updated = drink
        if old.builtIn != nil || BuiltInDrink(rawValue: old.id) != nil {
            updated.builtIn = old.builtIn
            updated.customName = old.customName
            updated.isArchived = false
        } else {
            updated.builtIn = nil
            if let name = updated.customName {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.customName = trimmed.isEmpty ? nil : trimmed
            }
        }
        updated.hydrationFactor = NutrientMath.clampHydration(updated.hydrationFactor)
        updated.defaultVolumeML = NutrientMath.clampVolume(updated.defaultVolumeML)
        c.drinks[index] = updated
        if updated.isArchived {
            c.presets.removeAll { $0.drinkID == updated.id }
        }
        commit(&c, now: now)
    }

    /// Archives a custom drink and removes its presets. Built-ins cannot be archived (no-op).
    public static func archiveDrink(in c: inout Catalog, id: String, now: Date = Date()) {
        guard BuiltInDrink(rawValue: id) == nil,
              let index = c.drinks.firstIndex(where: { $0.id == id }),
              c.drinks[index].builtIn == nil else { return }
        c.drinks[index].isArchived = true
        c.presets.removeAll { $0.drinkID == id }
        commit(&c, now: now)
    }

    /// Appends a preset. nil when the list already holds `Catalog.maxPresets`, or the drink is unknown or archived.
    @discardableResult
    public static func addPreset(to c: inout Catalog, drinkID: String, volumeML: Int, now: Date = Date()) -> Preset? {
        guard c.presets.count < Catalog.maxPresets,
              let drink = c.drink(id: drinkID), !drink.isArchived else { return nil }
        let preset = Preset(id: "preset-\(UUID().uuidString)", drinkID: drinkID,
                            volumeML: NutrientMath.clampVolume(volumeML))
        c.presets.append(preset)
        commit(&c, now: now)
        return c.presets.first { $0.id == preset.id }
    }

    /// Replaces the preset with the same id. Ignored when the id is unknown or the new drink is unknown or archived.
    public static func updatePreset(in c: inout Catalog, _ preset: Preset, now: Date = Date()) {
        guard let index = c.presets.firstIndex(where: { $0.id == preset.id }),
              let drink = c.drink(id: preset.drinkID), !drink.isArchived else { return }
        c.presets[index] = Preset(id: preset.id, drinkID: preset.drinkID,
                                  volumeML: NutrientMath.clampVolume(preset.volumeML))
        commit(&c, now: now)
    }

    public static func removePreset(from c: inout Catalog, id: String, now: Date = Date()) {
        guard c.presets.contains(where: { $0.id == id }) else { return }
        c.presets.removeAll { $0.id == id }
        commit(&c, now: now)
    }

    /// SwiftUI `onMove` semantics, implemented by hand (no SwiftUI in this package).
    public static func movePresets(in c: inout Catalog, from source: IndexSet, to destination: Int, now: Date = Date()) {
        let order = movedOrder(count: c.presets.count, source: source, destination: destination)
        guard order != Array(0..<c.presets.count) else { return }
        let original = c.presets
        c.presets = order.map { original[$0] }
        commit(&c, now: now)
    }

    public static func setDailyGoal(in c: inout Catalog, ml: Int, now: Date = Date()) {
        c.settings.dailyGoalML = UserSettings.clampGoal(ml)
        commit(&c, now: now)
    }

    public static func setWriteNutrients(in c: inout Catalog, _ on: Bool, now: Date = Date()) {
        c.settings.writeNutrients = on
        commit(&c, now: now)
    }

    /// The new order of the original indices after moving `source` in front of the element at `destination`.
    static func movedOrder(count: Int, source: IndexSet, destination: Int) -> [Int] {
        let moving = source.filter { $0 >= 0 && $0 < count }
        let target = min(max(destination, 0), count)
        let staying = (0..<count).filter { !source.contains($0) }
        let movedBefore = moving.filter { $0 < target }.count
        var order = staying
        order.insert(contentsOf: moving, at: min(max(target - movedBefore, 0), staying.count))
        return order
    }

    private static func commit(_ c: inout Catalog, now: Date) {
        c.revision = Catalog.nextRevision(after: c.revision, now: now)
        c.updatedAt = now
        c = c.sanitized()
    }
}
