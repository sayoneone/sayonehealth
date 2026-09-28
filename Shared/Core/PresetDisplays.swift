import SayoneCore

/// Preset buttons as plain display data, localized with `AppLanguage.current`. Reads the App Group
/// catalog on every call, so widgets and intents always see the latest presets.
enum PresetDisplays {
    static func all() -> [PresetDisplay] {
        AppGroup.catalog.load().presetDisplays(.current)
    }

    static func find(id: String) -> PresetDisplay? {
        all().first(where: { $0.id == id })
    }

    static func favorites(count: Int) -> [PresetDisplay] {
        Array(all().prefix(max(count, 0)))
    }

    static var builtInFallback: PresetDisplay {
        PresetDisplay.builtInFallback(.current)
    }
}

extension PresetDisplay {
    /// "Кола без сахара · 330 мл"
    var title: String {
        localizedTitle(.current)
    }
}

extension Drink {
    var displayName: String {
        name(.current)
    }

    var accusativeName: String {
        accusative(.current)
    }
}
