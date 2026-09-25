import Foundation

/// Composed runtime text (drink names, Siri dialogs, toasts) in Russian and English. Exact texts: §6.4.
public enum Phrasebook {
    public static func drinkName(_ d: BuiltInDrink, _ lang: AppLanguage) -> String {
        switch lang {
        case .ru:
            switch d {
            case .water: return "Вода"
            case .sparklingWater: return "Газированная вода"
            case .colaZero: return "Кола без сахара"
            case .coffee: return "Кофе"
            case .tea: return "Чай"
            case .juice: return "Сок"
            case .milk: return "Молоко"
            }
        case .en:
            switch d {
            case .water: return "Water"
            case .sparklingWater: return "Sparkling Water"
            case .colaZero: return "Cola Zero"
            case .coffee: return "Coffee"
            case .tea: return "Tea"
            case .juice: return "Juice"
            case .milk: return "Milk"
            }
        }
    }

    public static func drinkAccusative(_ d: BuiltInDrink, _ lang: AppLanguage) -> String {
        switch lang {
        case .ru:
            switch d {
            case .water: return "воду"
            case .sparklingWater: return "газированную воду"
            case .colaZero: return "колу без сахара"
            case .coffee: return "кофе"
            case .tea: return "чай"
            case .juice: return "сок"
            case .milk: return "молоко"
            }
        case .en:
            return drinkName(d, .en).lowercased()
        }
    }

    public static func genericDrink(_ lang: AppLanguage) -> String {
        lang == .ru ? "Напиток" : "Drink"
    }

    public static func logged(drinkName: String, volumeML: Int, summary: TodaySummary, savedToHealth: Bool,
                              healthAuthorized: Bool, _ lang: AppLanguage) -> String {
        let vol = VolumeFormat.short(volumeML, lang)
        let progress = VolumeFormat.progress(summary.waterML, goalML: summary.goalML, lang)
        var text: String
        switch lang {
        case .ru: text = "Записано: \(drinkName), \(vol). Сегодня \(progress)."
        case .en: text = "Logged \(drinkName), \(vol). Today: \(progress)."
        }
        if !savedToHealth {
            if healthAuthorized {
                text += lang == .ru ? " В «Здоровье» запишется позже." : " It will be saved to Health later."
            } else {
                text += " " + healthAccessMissing(lang)
            }
        }
        return text
    }

    public static func duplicateIgnored(_ lang: AppLanguage) -> String {
        lang == .ru ? "Уже записано." : "Already logged."
    }

    public static func storeFailed(_ lang: AppLanguage) -> String {
        lang == .ru
            ? "Не удалось записать. Разблокируйте устройство и повторите."
            : "Couldn't log the drink. Unlock the device and try again."
    }

    public static func today(_ s: TodaySummary, _ lang: AppLanguage) -> String {
        let progress = VolumeFormat.progress(s.waterML, goalML: s.goalML, lang)
        return lang == .ru ? "Сегодня выпито \(progress)." : "Today you've had \(progress)."
    }

    public static func undone(drinkName: String, volumeML: Int, _ lang: AppLanguage) -> String {
        let vol = VolumeFormat.short(volumeML, lang)
        return lang == .ru ? "Отменено: \(drinkName), \(vol)." : "Undone: \(drinkName), \(vol)."
    }

    public static func undoQueued(drinkName: String, volumeML: Int, _ lang: AppLanguage) -> String {
        let vol = VolumeFormat.short(volumeML, lang)
        return lang == .ru
            ? "Отменено: \(drinkName), \(vol). Из «Здоровья» удалится позже."
            : "Undone: \(drinkName), \(vol). It will be removed from Health later."
    }

    public static func nothingToUndo(_ lang: AppLanguage) -> String {
        lang == .ru ? "Нечего отменять." : "Nothing to undo."
    }

    public static func notDeletableHere(_ lang: AppLanguage) -> String {
        lang == .ru
            ? "Эту запись нужно удалить на устройстве, где она сделана, или в приложении «Здоровье»."
            : "Delete this entry on the device where it was logged, or in the Health app."
    }

    public static func healthAccessMissing(_ lang: AppLanguage) -> String {
        lang == .ru
            ? "Откройте SayoneHealth, чтобы разрешить доступ к «Здоровью»."
            : "Open SayoneHealth to allow access to Health."
    }

    public static func toast(drinkName: String, volumeML: Int, _ lang: AppLanguage) -> String {
        let vol = VolumeFormat.short(volumeML, lang)
        return lang == .ru ? "Записано · \(drinkName), \(vol)" : "Logged · \(drinkName), \(vol)"
    }
}
