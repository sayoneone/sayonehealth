import Foundation

/// Collapses widget/control double taps (D19). App taps are never collapsed.
public enum LogDedupe {
    public static let window: TimeInterval = 2

    /// Only when candidate.source == .widget: returns a visible existing entry with source .widget, same drinkID,
    /// same volumeML and |date difference| <= window. Otherwise nil.
    /// When several match, the one closest in time wins (the earlier one on a tie).
    public static func duplicate(of candidate: IntakeEntry, in existing: [IntakeEntry]) -> IntakeEntry? {
        guard candidate.source == .widget else { return nil }
        var best: IntakeEntry?
        var bestDistance = TimeInterval.infinity
        for entry in existing {
            guard entry.id != candidate.id,
                  entry.isVisible,
                  entry.source == .widget,
                  entry.drinkID == candidate.drinkID,
                  entry.volumeML == candidate.volumeML else { continue }
            let distance = abs(entry.date.timeIntervalSince(candidate.date))
            guard distance <= window else { continue }
            if distance < bestDistance || (distance == bestDistance && best.map { entry.date < $0.date } == true) {
                best = entry
                bestDistance = distance
            }
        }
        return best
    }
}
