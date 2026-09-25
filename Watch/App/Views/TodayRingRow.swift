import SwiftUI
import SayoneCore

/// Today's ring: a capacity gauge plus "1,2 из 2 л" and the pending-Health count.
struct TodayRingRow: View {
    let summary: TodaySummary

    var body: some View {
        HStack(spacing: 10) {
            Gauge(value: summary.progress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(verbatim: percentText)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: VolumeText.progress(summary))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if summary.pendingCount > 0 {
                    pendingLabel
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Uncapped share of the goal, e.g. "60%" or "125%".
    private var percentText: String {
        let goal = Double(max(summary.goalML, 1))
        let percent = Int((Double(summary.waterML) / goal * 100).rounded())
        return "\(percent)%"
    }

    private var pendingLabel: some View {
        Label {
            Text("Waiting for Health: \(String(summary.pendingCount))")
        } icon: {
            Image(systemName: "hourglass")
        }
        .font(.caption2)
        .foregroundStyle(.orange)
    }
}
