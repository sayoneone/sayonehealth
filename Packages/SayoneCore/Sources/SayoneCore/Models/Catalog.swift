import Foundation

/// Drinks, presets and settings. The phone authors it; the watch receives it (newest `revision` wins).
public struct Catalog: Codable, Hashable, Sendable {
    public static let currentVersion: Int = 1
    public static let maxPresets: Int = 12

    public var version: Int
    /// Int64 on purpose: epoch-ms overflows Int on arm64_32 watches.
    public var revision: Int64
    public var updatedAt: Date
    public var drinks: [Drink]
    /// Array order = display order; first 4 = iPhone favorites, first 3 = watch.
    public var presets: [Preset]
    public var settings: UserSettings

    public init(version: Int, revision: Int64, updatedAt: Date, drinks: [Drink], presets: [Preset], settings: UserSettings) {
        self.version = version
        self.revision = revision
        self.updatedAt = updatedAt
        self.drinks = drinks
        self.presets = presets
        self.settings = settings
    }

    /// Built-in drinks, default presets, default settings.
    public static func makeDefault(revision: Int64 = 0, now: Date = Date()) -> Catalog {
        Catalog(version: currentVersion,
                revision: revision,
                updatedAt: now,
                drinks: BuiltInCatalog.allDrinks,
                presets: BuiltInCatalog.defaultPresets,
                settings: UserSettings())
    }

    /// max(current + 1, epoch milliseconds of `now`). Never traps.
    public static func nextRevision(after current: Int64, now: Date) -> Int64 {
        let incremented = current < Int64.max ? current + 1 : Int64.max
        return max(incremented, epochMilliseconds(now))
    }

    /// `Int64(date.timeIntervalSince1970 * 1000)`, clamped so that it never traps.
    static func epochMilliseconds(_ date: Date) -> Int64 {
        let ms = (date.timeIntervalSince1970 * 1000).rounded(.towardZero)
        guard ms.isFinite else { return ms > 0 ? Int64.max : 0 }
        if ms >= 9.2e18 { return Int64.max }
        if ms <= -9.2e18 { return Int64.min }
        return Int64(ms)
    }

    /// First drink with this id, archived ones included.
    public func drink(id: String) -> Drink? {
        drinks.first { $0.id == id }
    }

    /// Drinks that are not archived, in catalog order.
    public var activeDrinks: [Drink] {
        drinks.filter { !$0.isArchived }
    }

    /// Presets with their drinks, in display order; presets whose drink is missing are skipped.
    public func resolvedPresets() -> [ResolvedPreset] {
        presets.compactMap { preset in
            drink(id: preset.drinkID).map { ResolvedPreset(preset: preset, drink: $0) }
        }
    }

    public func presetDisplays(_ lang: AppLanguage) -> [PresetDisplay] {
        resolvedPresets().map { PresetDisplay($0, lang: lang) }
    }

    /// Repairs anything a decoder, an old version or an editor bug could leave behind (§5.1, in order).
    public func sanitized() -> Catalog {
        var result = self

        // 1. Drop duplicate drink ids, keeping the first.
        var seenDrinks = Set<String>()
        var drinks: [Drink] = []
        for drink in result.drinks where !seenDrinks.contains(drink.id) {
            seenDrinks.insert(drink.id)
            drinks.append(drink)
        }

        // 2. Append missing built-in drinks, in BuiltInCatalog.allDrinks order.
        for builtIn in BuiltInCatalog.allDrinks where !seenDrinks.contains(builtIn.id) {
            seenDrinks.insert(builtIn.id)
            drinks.append(builtIn)
        }

        // 3. Clamp hydration, default volumes and preset volumes.
        for index in drinks.indices {
            drinks[index].hydrationFactor = NutrientMath.clampHydration(drinks[index].hydrationFactor)
            drinks[index].defaultVolumeML = NutrientMath.clampVolume(drinks[index].defaultVolumeML)
        }
        var presets = result.presets
        for index in presets.indices {
            presets[index].volumeML = NutrientMath.clampVolume(presets[index].volumeML)
        }

        // 4. Clamp the daily goal.
        result.settings.dailyGoalML = UserSettings.clampGoal(result.settings.dailyGoalML)

        // 5. Drop presets with duplicate ids, or whose drink is unknown or archived.
        var activeIDs = Set<String>()
        for drink in drinks where !drink.isArchived {
            activeIDs.insert(drink.id)
        }
        var seenPresets = Set<String>()
        var keptPresets: [Preset] = []
        for preset in presets where !seenPresets.contains(preset.id) && activeIDs.contains(preset.drinkID) {
            seenPresets.insert(preset.id)
            keptPresets.append(preset)
        }

        // 6. Truncate to maxPresets.
        if keptPresets.count > Catalog.maxPresets {
            keptPresets = Array(keptPresets.prefix(Catalog.maxPresets))
        }

        // 7. Current version.
        result.drinks = drinks
        result.presets = keptPresets
        result.version = Catalog.currentVersion
        return result
    }
}
