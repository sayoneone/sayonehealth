import Foundation

/// Volumes as text, formatted by hand so the output is identical on every platform.
/// U+00A0 NO-BREAK SPACE sits between number and unit; ru uses a decimal comma, en a decimal point.
public enum VolumeFormat {
    static let nbsp = "\u{00A0}"

    /// <1000: "250 мл"/"250 ml"; >=1000: "1 л","1,5 л"/"1 L","1.5 L"
    public static func short(_ ml: Int, _ lang: AppLanguage) -> String {
        if ml < 1000 {
            return "\(ml)" + nbsp + millilitreUnit(lang)
        }
        return liters(ml, lang)
    }

    /// "+" + short
    public static func plus(_ ml: Int, _ lang: AppLanguage) -> String {
        "+" + short(ml, lang)
    }

    /// <1000: "500"; >=1000: "1,5 л"/"1.5 L"
    public static func compact(_ ml: Int, _ lang: AppLanguage) -> String {
        if ml < 1000 {
            return "\(ml)"
        }
        return liters(ml, lang)
    }

    /// Always litres, at most one fraction digit: "0,3 л", "2 л" / "0.3 L", "2 L".
    public static func liters(_ ml: Int, _ lang: AppLanguage) -> String {
        litreNumber(ml, lang) + nbsp + litreUnit(lang)
    }

    /// "1,2 из 2 л" / "1.2 of 2 L"
    public static func progress(_ waterML: Int, goalML: Int, _ lang: AppLanguage) -> String {
        let word = lang == .ru ? "из" : "of"
        return litreNumber(waterML, lang) + " " + word + " " + liters(goalML, lang)
    }

    /// "1,2 / 2 л" / "1.2 / 2 L"
    public static func progressCompact(_ waterML: Int, goalML: Int, _ lang: AppLanguage) -> String {
        litreNumber(waterML, lang) + " / " + liters(goalML, lang)
    }

    // MARK: - Helpers

    static func millilitreUnit(_ lang: AppLanguage) -> String {
        lang == .ru ? "мл" : "ml"
    }

    static func litreUnit(_ lang: AppLanguage) -> String {
        lang == .ru ? "л" : "L"
    }

    /// `(Double(ml) / 100).rounded(.toNearestOrAwayFromZero) / 10` with at most one fraction digit;
    /// a trailing ",0" / ".0" is dropped.
    static func litreNumber(_ ml: Int, _ lang: AppLanguage) -> String {
        let tenthsDouble = (Double(ml) / 100).rounded(.toNearestOrAwayFromZero)
        // |ml| / 100 always fits in Int, even on 32-bit watches.
        let tenths = Int(tenthsDouble)
        let magnitude = tenths.magnitude
        let whole = magnitude / 10
        let fraction = magnitude % 10
        let sign = tenths < 0 ? "-" : ""
        if fraction == 0 {
            return sign + "\(whole)"
        }
        let separator = lang == .ru ? "," : "."
        return sign + "\(whole)" + separator + "\(fraction)"
    }
}
