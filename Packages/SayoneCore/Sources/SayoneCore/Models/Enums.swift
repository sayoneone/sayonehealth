import Foundation

/// The built-in drinks. The raw value is also the drink's catalog id.
public enum BuiltInDrink: String, Codable, CaseIterable, Sendable {
    case water, sparklingWater, colaZero, coffee, tea, juice, milk
}

/// Accent colour of a drink. Unknown raw values decode to `.blue` (forward compatible).
public enum DrinkTint: String, Codable, CaseIterable, Sendable {
    case blue, teal, brown, red, orange, green, purple, gray

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = DrinkTint(rawValue: raw) ?? .blue
    }
}

/// The device an entry was logged on.
public enum DeviceKind: String, Codable, CaseIterable, Sendable { case phone, watch }

/// Where an entry stands with respect to Apple Health.
public enum HealthSyncStatus: String, Codable, CaseIterable, Sendable {
    /// Journaled; not known to be in Health yet.
    case pending
    /// This device saved its samples.
    case saved
    /// The user deleted it; samples may still exist; hidden everywhere.
    case pendingDelete
    /// Tombstone; samples removed or never existed; hidden; pruned after 8 days.
    case deleted
}

/// One HealthKit quantity written per entry. `allCases` is the write and delete order.
public enum HealthComponent: String, Codable, CaseIterable, Sendable { case water, caffeine, energy, sugar }

/// What triggered a log. Controls use `.widget`. Unknown raw values decode to `.app`.
public enum LogSource: String, Codable, CaseIterable, Sendable {
    case app, widget, siri, deepLink

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = LogSource(rawValue: raw) ?? .app
    }
}

/// The language composed runtime text is produced in.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case en, ru

    /// The first element starting with "ru" (case-insensitive) gives `.ru`; anything else gives `.en`.
    public init(preferredLocalizations: [String]) {
        if let first = preferredLocalizations.first, first.lowercased().hasPrefix("ru") {
            self = .ru
        } else {
            self = .en
        }
    }
}

/// Phone = author (owns catalog edits), watch = replica (applies pushes).
public enum CatalogRole: Sendable { case author, replica }

extension AppLanguage {
    /// The language the running bundle resolved to. Internal: the apps use `AppLanguage.current` (Shared/Core).
    static var bundleDefault: AppLanguage {
        AppLanguage(preferredLocalizations: Bundle.main.preferredLocalizations)
    }
}
