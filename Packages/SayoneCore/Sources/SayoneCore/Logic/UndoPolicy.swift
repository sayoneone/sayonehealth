import Foundation

/// Undo windows (D18) and which entry an undo removes.
public enum UndoPolicy {
    /// Widget and in-app undo: 10 minutes.
    public static let widgetWindow: TimeInterval = 600
    /// Voice undo: 3 hours.
    public static let voiceWindow: TimeInterval = 10_800
    /// In-app toast lifetime.
    public static let toastDuration: TimeInterval = 5

    /// Newest visible entry with now - date in 0...window, else nil.
    public static func candidate(in local: [IntakeEntry], now: Date, window: TimeInterval) -> IntakeEntry? {
        guard window >= 0 else { return nil }
        var best: IntakeEntry?
        for entry in local where entry.isVisible {
            let age = now.timeIntervalSince(entry.date)
            guard age >= 0, age <= window else { continue }
            if let current = best, current.date >= entry.date { continue }
            best = entry
        }
        return best
    }
}
