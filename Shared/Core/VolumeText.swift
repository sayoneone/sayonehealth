import SayoneCore

/// SayoneCore.VolumeFormat in the current language. The results are already localized: render them with
/// `Text(verbatim:)` or a `String` variable.
enum VolumeText {
    static func short(_ ml: Int) -> String {
        VolumeFormat.short(ml, .current)
    }

    static func plus(_ ml: Int) -> String {
        VolumeFormat.plus(ml, .current)
    }

    static func compact(_ ml: Int) -> String {
        VolumeFormat.compact(ml, .current)
    }

    static func progress(_ s: TodaySummary) -> String {
        VolumeFormat.progress(s.waterML, goalML: s.goalML, .current)
    }

    static func progressCompact(_ s: TodaySummary) -> String {
        VolumeFormat.progressCompact(s.waterML, goalML: s.goalML, .current)
    }
}
