import Foundation

public enum WidgetTimeline {
    public static let refreshInterval: TimeInterval = 1800

    /// min(now + refreshInterval, nextDayStart(after: now), undoUntil if undoUntil > now)
    public static func nextRefresh(after now: Date, undoUntil: Date?, calendar: Calendar = .current) -> Date {
        var next = min(now.addingTimeInterval(refreshInterval), TodayMath.nextDayStart(after: now, calendar: calendar))
        if let undoUntil = undoUntil, undoUntil > now, undoUntil < next {
            next = undoUntil
        }
        return next
    }
}
